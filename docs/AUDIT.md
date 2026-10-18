# Codebase audit — 2026-10-17

Five parallel audits (data layer · Bitcoin/network · import pipeline ·
AI/inference · UI/state) over ~25k lines. Every finding below was verified
against the source; anything that could not be substantiated was dropped.

Fixed items are done and tested on `fix/codebase-audit`. The rest are listed
with enough detail to act on without re-auditing.

---

## Fixed

### Build
- **The working tree did not compile.** `electrum_service.dart` and
  `bitcoin_node_service.dart` referenced eight `AppConstants` keys that were
  never added (16 analyzer errors). Keys added; `settingBitcoinDataSource` too.
- **`BitcoinNodeService` could not save its RPC password on macOS** — it built
  its own `FlutterSecureStorage` without `useDataProtectionKeyChain: false`,
  the exact config already documented as failing with
  `errSecMissingEntitlement` on this ad-hoc-signed target. Now goes through
  `SecureKeyStore`, which gained `readEntry/writeEntry/deleteEntry` so there is
  one place that knows the platform quirks.
- Removed `shared_preferences` (declared, never imported — a native plugin in
  all six platform builds). Declared `path`, which `database.dart` now imports.

### Bitcoin / xpub — `lib/core/services/xpub_service.dart` (rewritten)
Two independent root causes of the reported *"0 transactions imported, scanned
20 addresses"* for a wallet with known history:
- **A blank server field stored `''` as the live base URL**, so every request
  became a relative URL that threw, and every throw was swallowed into "this
  address is unused" — 20 of those end the scan and report success. It only
  looked intermittent because the next launch mapped `''` back to the default.
  `saveSettings` now normalises (scheme, host, trailing slashes), never holds
  an unusable value, and returns null so Settings can say it rejected a typo.
- **Network failure was indistinguishable from an empty address.** `_fetchAddressTxs`
  returned `[]` for timeouts, DNS failure, non-200 and bad JSON. It now throws
  `XpubSyncException`, retries 429/5xx with backoff honouring `Retry-After`,
  and both call sites already surface it.

Also fixed in the same file:
- **The change chain (`m/1/i`) was never derived.** Only chain 0 was scanned, so
  every change output was invisible: any wallet that had ever spent showed the
  whole input leaving and nothing coming back. Both chains are now scanned with
  independent gap counters. Pinned by the BIP84 vector in
  `test/xpub_service_test.dart`.
- **Testnet keys produced mainnet addresses.** `upub`/`vpub` were recognised but
  the address encoder hardcoded `0x00`/`0x05`/`bc`, and `tpub` fell through to
  mainnet legacy. Format *and* network now come from the 4-byte version prefix,
  unknown versions and extended private keys are rejected, and testnet encodes
  `0x6F`/`0xC4`/`tb`.
- **One on-chain transaction became N rows** (one per address it touched, salted
  by address). Net effect is now computed per txid against the complete owned
  address set — which also means a self-send correctly shows the fee instead of
  being dropped as a zero. Stale rows from the old scheme are deleted on rescan,
  so wallets heal themselves.
- **History was silently truncated at 25 transactions per address** — no
  pagination. Now follows `/txs/chain/:last_seen_txid`.
- Historical prices were fetched twice for every date (two passes); now once.
  The whole transactions table was loaded to build a hash set; now one
  projected column. Inserts are wrapped in a single DB transaction, so listeners
  see one change rather than one per row. One shared `http.Client`.

### Backup & restore — `settings_screen.dart`, `database.dart`
- **Export and import used a path the database never opens.** Settings built
  it from `getApplicationSupportDirectory()`; `driftDatabase(name:)` resolves to
  `getApplicationDocumentsDirectory()`. Export always said "Database file not
  found", and **import copied the backup to a path nothing reads and then told
  the user the restore had succeeded** — the worst case being a user who resets
  their data expecting to restore it. One `databaseFile()` helper in
  `database.dart` is now the only way to reach the file.
- Export uses `VACUUM INTO` (a byte copy of a live rollback-journal database can
  be torn — a backup that fails only when needed). Import verifies the SQLite
  magic header and keeps a `.bak` of the database it replaces, so picking the
  wrong file is survivable.

### Import pipeline — `import_service.dart`
- **European decimal commas were parsed as 100–1000× the real amount.**
  `-12,50` became `-1250.00`. Separator is now inferred per value.
- **A charge and its same-day refund collapsed into one row.** The main-table
  dedup hash used `tx.amount`, which is always positive, so the refund hashed
  identically and was dropped by `insertOrIgnore`. Now hashes the signed amount,
  salted per wallet so the same rent figure in two accounts no longer collides.
- **UK dates had month and day swapped for days 1–12 only** (`03/04/2025` → 3
  March, from an April row). Order is now inferred once per file from the whole
  date column. Dotted dates (`01.02.2025`) parse at all now.
- **Wells Fargo lost its first transaction on every import** — `skipHeaderRow`
  existed on the profile and was referenced nowhere. Wired through.
- A UTF-8 BOM broke header detection for every bank that exports one;
  Windows-1252 exports (`£`, `é`) threw and were reported as an unrecognised
  layout; semicolon/tab-delimited files parsed as one unusable column. All three
  fixed (BOM strip, Latin-1 fallback, delimiter sniffing).
- A single amount column with no negative in it is no longer treated as signed,
  which booked every credit-card charge as income. `DR`/`CR` suffixes parse.
- Imported rows no longer land on an arbitrary wallet (`wallets.first` was
  unordered and could be an xpub wallet).

### Privacy — the disclosure now matches the code

Addressed 2026-10-18. The audit found the enum labels all factually correct;
what was wrong was the call sites, and one claim the code did not keep.

- **The monthly insight no longer generates by itself for a provider that would
  receive it.** `dashboard_screen.dart` auto-generated it from `initState`, so
  selecting Claude in Settings and opening the Dashboard uploaded the month's
  income, spending, surplus, stack total and full category breakdown to a third
  party with no user action — and swallowed any error. It now generates
  automatically only when the backend keeps the data on hardware the user
  controls; otherwise `AiInsightCard` offers a button naming the recipient, and
  nothing is sent until it is pressed.
- **Statements are no longer handed to a third party without asking.** The AI
  tier is tried *first* for every CSV and PDF, so with a hosted provider
  selected the raw file went to it before anything local was attempted, and no
  screen in the import flow said so. `ImportService` now gates that tier on
  consent recorded per provider (`AppConstants.aiImportConsentKey`), the import
  screen asks with the disclosure inside the dialog, and declining falls
  through to the local tiers — rules for a CSV, heuristics for a PDF. A photo
  of a statement has no local route, so declining ends the import with
  "Nothing was sent" rather than a parse failure.
- **"Nothing is sent until you ask" is now true**, and the disclosure says it
  for all three paths — question, insight, statement — instead of mentioning
  only questions and so implying the other two do not happen.
- **LM Studio and Ollama no longer claim privacy they cannot deliver.**
  `isPrivate` was hardcoded true for LM Studio next to the words "Nothing
  leaves your device", while its base URL is free text the user can point
  anywhere. Both backends now derive the claim from the configured host
  (`OllamaService.isLocalEndpoint`: loopback, `.local`, link-local and the
  RFC 1918 ranges), and a remote self-hosted server is disclosed by host name.
  That flag is what now gates automatic insight generation and the AI import
  tier, so its accuracy matters more than its wording.
- **A 401 body no longer reaches the screen.** `describeError` preferred the
  provider's own message for every status, and OpenAI's 401 contains
  `Incorrect API key provided: sk-proj-ab****XYZ` — a partial copy of the
  user's key, printed verbatim by the chat screen and into any screenshot.
  Auth failures now use the canned string.

Covered by `test/ai_privacy_test.dart`: the local/remote host classification,
the enum invariant, and that consent defaults to no, is remembered, and does
not carry from one provider to another.

### The legacy import pipeline is gone

`CsvImportService` and `CsvImportSheet` are deleted (~850 lines). Nothing
constructed the sheet — `/import` routes to `ImportFileScreen` and
`ImportService` — so the entire second pipeline was unreachable, and with it
went the silent 100-row cap, the rejection of 2-digit years, a `_parseAmount`
with no decimal-comma, DR/CR or parenthetical-negative handling, a third
divergent category colour map, a duplicate `_autoCategory`, a hardcoded
`fiatCurrency: 'USD'`, and seven missing `mounted` guards.

### Notifications work on iOS

`InitializationSettings` passed no `iOS:` block and only the macOS permission
plugin was resolved, so on the TestFlight build no permission was ever asked
for and no notification could appear. All three platforms are now asked
(including Android 13+, where `POST_NOTIFICATIONS` became a runtime
permission), once per session rather than per notification;
`UNUserNotificationCenter.current().delegate` is set in `AppDelegate` so a
notification raised while the app is in the foreground is not swallowed; budget
IDs are offset so `categoryId * 2 + 1` can no longer collide with the
stack-goal ID at category 4999; and `BudgetProgress.isOverBudget` guards a zero
budget, which used to produce "you've exceeded your $0 Food budget by $47".
Verified with `flutter build ios --no-codesign`.

---

### Currency is the one the user chose

Addressed 2026-10-18.

- **A manual entry stored `fiatCurrency: 'USD'`** whatever the active currency
  was, while the list renders using the stored value — a GBP user's £40 expense
  displayed as "-$40.00", and its sats had been derived from the GBP price, so
  the two halves of the same row disagreed. The sats→fiat hint hardcoded `$`
  the same way. An edit now rewrites `fiatCurrency` as well, because it
  recomputes the amount at the current rate.
- **The per-source currency was collected and then discarded.** Every parse
  path in `import_service.dart` hardcoded `'USD'`, so the choice made in
  `ImportSourceSetupScreen` reached nothing. It now threads through the rules,
  profile, manual-mapping, PDF-heuristic and both AI tiers, where it is also
  the fallback for a row whose currency the model omitted.
  `InstitutionProfile.defaultCurrency` is gone: a profile identifies a column
  layout, and the user is the authority on what the account holds.
- **A BTC-denominated import wrote BTC units into `amountFiat`**, which
  `DashboardService` sums as money, so a 0.05 BTC deposit read as "$0.05".
  `amountFiat` is now derived from the sats via the historical price for that
  date — the same shape as the xpub path — with spot as the fallback and 0 when
  neither resolves, so the column never carries a BTC figure.

Covered by `test/import_service_test.dart`.

### Months tile the timeline

Addressed 2026-10-18. Seven aggregates built a closed range ending at
`23:59:59` and tested it with `!isAfter(end)`. `DateTime` carries milliseconds,
so the last 999 ms of every month belonged to no month at all: absent from the
dashboard, from analytics, from the budget it should have counted against, from
the per-wallet breakdown and from the exported summary. Reachable without
trying, because the add-transaction sheet seeds the date with `DateTime.now()`.

A half-open `DateRange` (`lib/shared/utils/date_range.dart`) is now the only
place that knows the rule, so consecutive months tile the timeline exactly.
`test/month_boundary_test.dart` pins a transaction at 23:59:59.400 on the last
day of a month through all six aggregates, and sweeps every millisecond either
side of a boundary asserting exactly one month claims it.

### A category rename takes its transactions with it

Addressed 2026-10-18. `Transactions.category` is free text and
`BudgetService.getProgress` joins on the name, not the id, so renaming a
category orphaned every transaction in it: the budget card dropped to "$0 of
$500", no overspend alert could fire, and the pie chart kept a phantom slice
under the old name. `updateCategory` now rewrites `transactions`,
`importedTransactions` and `descriptionCategoryMappings` in the same
transaction as the rename — the mapping table too, or the next import
re-learns a name that no longer exists. `test/category_rename_test.dart`.

### A budget cannot be broken by a double tap

Addressed 2026-10-18. `BudgetService.upsert` was a read-then-write with no
transaction over a table with no unique index, so double-tapping Save inserted
twice and every later upsert for that category threw `StateError` out of
`getSingleOrNull` — the budget could not be edited again without clearing the
data. The write is one transaction now and `budgets.categoryId` carries a
unique index, added in a **v6 migration** that collapses any duplicates an
older install accumulated before creating it (the index cannot be created over
them). `migrateToV6` is a named method so the test runs the real statements;
there is no generated schema history to migrate against.

### Streams are built once, not once per frame

Addressed 2026-10-18. Every `watch*()` returns a new Drift stream, so a
`StreamBuilder` fed from inside `build()` re-subscribed and reset to `waiting`
on each rebuild. Every keystroke in the transactions search box replaced the
list with a spinner and re-queried the table; the dashboard's Wallets section
vanished and came back on every BTC price tick. Each stream is now built in
`initState` and rebuilt only when its month — or, for the dashboard, the
inflation rate baked into the aggregate — actually changes, with the
`ValueListenableBuilder`s moved inside the `StreamBuilder` so a price or
currency tick only repaints.

Two per-row futures went with them: the transactions screen ran
`categoryService.getAll()` in a `FutureBuilder` per visible row, and the
dashboard did the same for its recent-transaction list on every price tick.
Both now read a name → category map the screen watches once, so a rename or a
colour change still reaches the list.

`watchDashboard` watched only `transactions` while `_compute` reads the stack
goal from `AppSettings` — harmless only for as long as the widget tree rebuilt
the stream constantly. It watches both now, and `watchPerWallet` watches
`wallets` as well.

### Bulk imports commit once

Addressed 2026-10-18. The save loop in `import_service.dart` now runs in one
`db.transaction`. Each commit used to fire `transactions.watchAll()`, which
main.dart turns into a budget re-check plus three full table selects, and woke
every mounted `StreamBuilder`: a 300-row import meant hundreds of full scans
and a multi-second freeze, and a kill mid-loop left the two tables
inconsistent. A test asserts 25 rows wake listeners once.

### One rule for the AI tab

Addressed 2026-10-18. CLAUDE.md claimed Settings and onboarding could not
drift; they had. Settings omitted the "hosted provider with a key" term
onboarding had, so a mobile user with a saved Anthropic key lost the AI tab by
switching provider and back — and saving a key, which is all a hosted provider
needs, did not update the flag at all. `main.dart` seeded it from
`isDesktop || isConnected`, where an on-device provider's `isConnected` is a
readiness probe `loadSettings` only kicks off, so on-device providers lost the
tab after every restart.

`OllamaService.aiShouldBeEnabled` is now the one rule and all three read it
(Settings had eleven inline copies). `isUsableWithoutDesktop` holds the part
that is not about the host platform, so `test/ai_enabled_test.dart` can pin it
without pretending to be a phone.

`/ai` also redirects to `/dashboard` when the tab is gone. The path was only
dropped from the shell's tab list, so `_indexForLocation` fell back to 0 and
the AI screen stayed rendered with Dashboard highlighted and no tab matching
it. The router takes `aiEnabledNotifier` as its `refreshListenable`, so this
re-runs on the toggle rather than at the next navigation.

### A failed answer is no longer saved as a complete one

Addressed 2026-10-18. A provider error frame arriving after 200 tokens was
invisible: `extractDelta` returns null for it, so the stream ended cleanly and
the truncated answer was persisted as complete. `CloudBackend` now recognises
each provider's error frame and throws, and recognises the stop reason that
means the answer hit the output cap — `maxOutputTokens`, a named constant
rather than a literal 4096 in two places — which the answer now says.
Covered in `test/cloud_backend_test.dart`.

### Editing an imported Bitcoin row keeps its value

Addressed 2026-10-18. The edit sheet's amount field was always formatted with
`toStringAsFixed(2)`, so an 0.00047 BTC row opened as "0.00" and saving wrote
0.0 straight past the `< 0` guard. The field is now denominated in whatever the
row is — sats for a Bitcoin row, with the fiat value derived from the price
rather than typed, and eight decimals for a BTC-denominated parsed row — and
zero is rejected rather than only negatives.

### Light mode reaches the Stack screen

Addressed 2026-10-18. The hero card's fixed `0xFF1A1200`/`0xFF2A1F00` gradient
under white text and the chart's 5 %-opacity white gridlines were survivors of
the light-mode pass recorded as complete in CLAUDE.md: in light mode the card
stayed a dark brown slab and the gridlines were invisible. Both are derived
from the theme now.

### Notifications come from one place

Addressed 2026-10-18. `budgets_screen.dart` fired an over-budget notification
from inside `build()`, through a bare `FlutterLocalNotificationsPlugin()` that
was never initialised — so on iOS no permission had been asked for and nothing
appeared, bypassing the whole iOS notification fix above — keyed on
`budget.id`, which can collide with the stack-goal id, and deduplicated by a
module-level `Set` that was never cleared, so re-exceeding a budget in the same
month never alerted again. The screen holds its progress stream in state and
hands the check to `BudgetService.checkAndNotify`, the path main.dart already
uses.

### Guards after an await

Addressed 2026-10-18. The seven `setState()`-after-dispose paths the audit
named: three connection-test failure branches in `settings_screen.dart` (where
the `!mounted` check happened before the awaits that follow), its export,
import and Esplora non-200 branches, plus `add_transaction_sheet`,
`set_budget_sheet` and `stack_screen._saveGoal`.

---

## Not fixed — highest value first

P1 is clear as of 2026-10-18; everything below was judged worth doing but not
urgent, and the detail is here so it can be acted on without re-auditing. Line
numbers were accurate on 2026-10-17 and most files have moved since.

### P2 — worth doing, not urgent

- `BudgetService.watchProgress` double-fires on first listen — `onListen` sets
  up two watches that each emit immediately *and* calls `update()` — and
  `onCancel` cancels the subscriptions without closing the controller.
  `watchPerWallet` still re-scans all transactions once per wallet.
- `generateDueRecurring` resurrects a *deleted latest* instance, because the
  resume point is the latest surviving row. Persist a per-series index.
- Price service: `switchCurrency` deliberately clears the in-flight guard
  (`btc_price_service.dart:104`), so two fetches can interleave and persist a
  partial map; a partial mempool response clears `_allPrices` before checking;
  `priceNotifier` can hold the old currency's number after a switch; the
  `priceUsd` column stores whatever the active currency was.
- Auto-categorisation matches bare substrings and then **persists the result —
  including the `'Other'` default — as a learned mapping**, permanently pinning
  that merchant. This is the real cause of "everything lands in Other": the
  categoriser does run and does persist. Verified misses: `METRO BANK CHARGE` →
  Transport, `RENT A CAR HERTZ` → Housing, `PASSPORT OFFICE` → Entertainment,
  `MONTHLY FEE REFUND` → Income. Match on word boundaries, score all matches,
  and only persist user edits.
- Receipt import base64-encodes the photo whole with no downscale (a 4 MB photo
  becomes ~5.5 MB and the provider 400s); chat re-sends the entire transcript
  every turn with no trimming; streaming requests time out only on headers, not
  on an idle body; the chat stream is never cancelled, so leaving the tab keeps
  billing and still saves the answer; concurrent on-device EventChannel
  listeners clobber each other; model pickers offer embedding/TTS models.
- `rpcCall` decodes the body before checking the status, so a wrong RPC password
  surfaces as `FormatException`. Electrum TLS accepts any certificate
  (`onBadCertificate: (_) => true`) with no pinning — on hostile Wi-Fi that
  hands an attacker the user's entire derived address set.
  `ElectrumSession.call` leaks a pending completer on every timeout.
- xpub derivation runs on the UI isolate; there is no scan cursor, so every
  rescan re-fetches from index 0 on both chains.
- Onboarding's Bitcoin-server page is a non-scrolling `Column` with a text
  field — RenderFlex overflow on a small phone when the keyboard opens.
  `_onboardingRedirect` issues a DB select on every navigation.
  Settings rebuilds its whole 1,724-line tree on every keystroke in the API-key
  and server fields.

### Duplication / shape
- Sats formatting is reimplemented about a dozen times with the same regex and
  subtly different sign handling, while `SatConverter.formatSats` exists and is
  used in 6 places. The category colour map exists **3 times with divergent
  colours** (Shopping is purple, blue or grey depending on the screen) and none
  of them consults the user's own per-category colour from the DB — though the
  transactions list and the dashboard's recent rows now at least receive the
  user's `Category` row, so the colour is available to them. `_SectionHeader` ×4,
  month selector ×3 with the arithmetic triplicated.
- `sat_amount_display.dart` (95 lines) is dead code; so are `ElectrumService`,
  `BitcoinNodeService`, `BitcoinDataSource` and `ManageWalletsSheet` — they
  compile but nothing references them.
- `settings_screen.dart` (1,724), `onboarding_screen.dart` (1,745) and
  `stack_screen.dart` (1,156) each want splitting; `on_device_ai_section.dart`
  is the precedent.

### The schema can be trusted (v7)

Addressed 2026-10-18.

- **Indexes exist.** The schema had almost none, so every month range,
  per-wallet total, budget grouping and launch-time recurring scan was a full
  table scan. `transactions.(date, walletId, category, recurringPeriod)`,
  `importedTransactions.sourceId` and a unique
  `descriptionCategoryMappings.(sourceId, description)` are indexed by
  `migrateToV7`, which collapses pre-existing duplicate mappings first, as v6
  did for budgets. `schema_integrity_test.dart` asserts each index exists and
  that a month-range query plans against `idx_transactions_date` rather than
  scanning.
- **Foreign keys are enforced.** sqlite ignores them unless asked, per
  connection, so every `.references(...)` was decorative: a transaction could
  point at a deleted wallet and nothing would complain until something read it
  back. `beforeOpen` now issues `PRAGMA foreign_keys = ON` — after the migrator,
  since a migration that rebuilds a table legitimately breaks references while
  it runs. Tested, including that the seed and `resetAndReseed` both satisfy it.
- **Learned categories are written once per import, not four times per row.**
  `_saveDescriptionMappings` deleted and inserted per row, awaited; it now
  collapses in memory and writes one batch of upserts against the new unique
  index.

### Test gaps
Month-boundary aggregation, `getProgress` after a category rename, the v6
migration and the AI-tab rule are covered now (`month_boundary_test.dart`,
`category_rename_test.dart`, `ai_enabled_test.dart`). Still uncovered: a
v1→v6 migration against a fresh `onCreate` — there is no generated schema
history to migrate against, which is why `migrateToV6` is a named method the
test calls directly — the dedup-hash contract across the three salts, and
widget-level stream reactivity (the import save path's single-commit guarantee
is asserted at the service level).

---

## Verified correct (no action)

- BIP32 CKDpub: 37-byte `serP(Kpar) || ser32(i)`, `IL >= n` rejected,
  point-at-infinity checked, chain code `IR`. P2SH-P2WPKH redeem script and
  bech32 v0 encoding are right. `_parseExtKey` offsets are right.
- The migration strategy itself: cumulative `if (from < n)` steps, seeds only in
  `onCreate`, v1→v5 lands on the same schema as a fresh create.
- Recurring date arithmetic (calendar fields, anchor-derived, month-end and
  Feb 29 clamped) and `TransactionService.update`'s use of `write` over
  `replace` — both well tested.
- No sats truncation anywhere: every fiat↔sats conversion rounds.
- Secrets: no API key in `AppSettings`, none logged, none in a URL; the legacy
  `maple_api_key` row is deleted only after a confirmed keychain write.
- Streaming UTF-8 uses the stateful decoder on every path, and `cloud_backend`
  buffers SSE frames across chunk boundaries correctly. Anthropic, Gemini and
  OpenAI wire formats match their docs.
