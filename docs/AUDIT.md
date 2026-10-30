# Codebase audit — 2026-10-17

Five parallel audits (data layer · Bitcoin/network · import pipeline ·
AI/inference · UI/state) over ~25k lines. Every finding below was verified
against the source; anything that could not be substantiated was dropped.

Everything here is fixed and on `main`. Forward-looking work lives in
[`TODO.md`](TODO.md); this file is the record of what was wrong and why, kept
so none of it has to be re-investigated.

---

## What is left

Nothing from the 2026-10-17 audit is open. The third pass (2026-10-21, at the
end of this file) left items open; they are in `TODO.md` item 15. The three P2
items that were still listed here on 2026-10-18 — streaming idle timeouts, the on-device channel collision, and
the per-navigation database read in the router redirect — are fixed below.

Forward-looking work lives in **[`TODO.md`](TODO.md)**, which is the single
list. Two things this audit surfaced are tracked there rather than here,
because they are features and judgement calls rather than defects:

- Wiring up the Bitcoin data-source picker, which is what the dead
  `ElectrumService` / `BitcoinNodeService` code exists for.
- Reducing the xpub scan's request count. (Derivation is off the UI isolate
  now; the scan cursor once proposed here is not safe — see TODO.md.)
- Decomposing `settings_screen.dart`, which needs a design change rather than
  the file move the other two screens got.
- The remaining test gaps, and the fact that `CLAUDE.md` is gitignored so its
  stale SDK and schema versions cannot be corrected by a commit.

### Two claims this report got wrong

Recorded because a reader would otherwise go looking for work that should not
be done:

- **`_SectionHeader` is not a four-way duplicate** and the month selector is
  not a three-way one. The four headers are *two* designs (title-case with an
  action link, versus uppercase label with a trailing widget) at three
  different paddings, and the Analytics month selector uses `IconButton` and
  `titleMedium` where the shared one uses `GestureDetector` and `titleSmall`.
  Merging either would change what is on screen. The genuinely duplicated part
  was the month arithmetic, now `MonthCursor`.
- **The `add-claude-github-actions` branch did not have 30 unmerged commits.**
  It had an unrelated history — no common ancestor with `main` — so those
  commits were this project's own history under different ids. The only unique
  content was two workflow files, now on `main`.

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

### Aggregates read once, and a deleted instance stays deleted

Addressed 2026-10-18.

- `BudgetService.watchProgress` ran its whole aggregate three times on first
  listen (two watches that each emit immediately, plus an explicit call) and
  once per row during a burst of inserts. Reads are now coalesced into a
  microtask and serialised, and `onCancel` closes the controller — without
  which `controller.isClosed` was always false, so every guard on it was dead
  and the controller itself was never released. `getProgress` filters the month
  in SQL against the v7 `date` index instead of reading every transaction ever
  recorded, and resolves categories through two maps rather than a linear scan
  per row.
- `_computePerWallet` grouped transactions by wallet with a `where` inside the
  wallet loop, making it O(wallets × transactions) on the UI isolate; it now
  groups in one pass.
- `generateDueRecurring` no longer resurrects a deleted instance. The resume
  point was the latest *surviving* row, so deleting the newest one lowered it
  and the next launch recreated that row identically — while deleting a middle
  instance did not, which made it inconsistent too. A per-series high-water
  mark in `AppSettings` (`AppConstants.recurringCursorKey`) only moves forward.
  Both cases are tested.

### The price map cannot be half-destroyed

Addressed 2026-10-18. Every fiat figure in the app is one conversion away from
this number, so each of these was wrong money on every screen at once.

- The two fetchers cleared `_allPrices` *before* knowing whether the response
  held anything, so a partial reply — or a mempool failure followed by a
  CoinGecko failure — left the map stripped of currencies it already had, and
  that stripped map was then persisted. They now build and return their own
  map, and the caller swaps it in only on success.
- `switchCurrency` cleared the in-flight guard with the comment "in case a
  stale lock is held", which let two fetches run at once and interleave their
  writes. The guard is left alone now.
- Switching to a currency with no data left `priceNotifier` holding the
  previous currency's number while the getter already reported the new one —
  every figure relabelled rather than reconverted, out by the exchange rate,
  with nothing shown to the user. It is now set to null, which the UI renders
  as loading. Tested.
- `initialize` fell back to the `priceUsd` column, which holds whatever
  currency was active when it was written and records no currency of its own,
  so a EUR user could be shown a USD figure. It is read for its timestamp
  only; the all-prices map is the real cache.
- mempool's `/v1/prices` returns a `time` field beside the currencies, which
  was stored as a price of "TIME" — a Unix timestamp — and persisted.
  `currencyEntries` keeps 3-letter codes with numeric values and drops the
  rest. Tested.

### Imported rows stop landing in Other and staying there

Addressed 2026-10-18. This is the complaint in `SatsStackNotes.md`, and the
categoriser was not the only cause.

- **Keywords matched inside words.** A bare `contains` made `PASSPORT OFFICE`
  Entertainment (`sport`), `BARBERSHOP` Shopping (`shop`) and
  `CURRENT ACCOUNT FEE` Housing (`rent`). Matching is now bounded by
  lookarounds rather than `\b`, because several keywords end in punctuation —
  `disney+`, `at&t`, `chick-fil` — where `\b` asserts the opposite.
- **The first match won, not the best.** Categories live in a map, so the order
  was arbitrary: `MONTHLY FEE REFUND` was Income because Income's `refund`
  came before Subscriptions' `monthly fee`. The longest match now wins, which
  also lets a specific phrase override a general one — `rent a car` beats
  Housing's `rent`.
- **The fallback was learned.** Every included row wrote a description →
  category mapping, `'Other'` included, and that mapping was re-applied to
  every later import of the same source — so one unrecognised merchant was
  pinned to Other permanently, and improving the keyword list changed nothing
  for it. `ParsedTransaction.categoryIsFallback` marks a guess, guesses are not
  learned, and `setUserCategory` clears the mark when the user picks one.

`METRO BANK CHARGE` → Transport is the one case left: `metro` genuinely is a
whole word there, and no amount of scoring fixes it. It needs either a
negative-keyword list or the user's own correction, which is now learned.

Tested in `auto_category_test.dart`, with every misclassification above as a
case.

### The Bitcoin plumbing is honest about failure

Addressed 2026-10-18. None of this is wired into a screen yet, but it compiles
and is the next feature up, so it is better fixed before it ships.

- **Electrum verified no certificates at all** —
  `onBadCertificate: (_) => true`, for the convenience of self-signed servers.
  On a hostile network that lets anyone sit in the middle of the connection and
  harvest the full set of addresses a wallet scan asks about, which
  deanonymises the whole wallet, while returning empty history so nothing looks
  wrong. Certificates are verified; a self-signed server is used by pinning its
  fingerprint first (`fetchCertificateFingerprint` probes without proceeding),
  and only that certificate is accepted afterwards.
- `ElectrumSession.call` applied its timeout to the returned future, leaving
  the completer in `_pending` for the life of the socket — one leak per
  timed-out request. The timeout removes its own entry now.
- `rpcCall` decoded the body before looking at the status, and Bitcoin Core
  answers a bad credential with 401 and a non-JSON body, so "wrong password"
  surfaced as `FormatException: Unexpected character` and a 403 from
  `rpcallowip` was indistinguishable from it.

### The AI paths stop wasting and leaking

Addressed 2026-10-18.

- **A receipt photo is downscaled before it is sent.** It was base64-encoded
  whole: a 3–5 MB camera photo becomes ~6 MB encoded, and every hosted provider
  rejects that (Anthropic caps an image at 5 MB and ~1,568 px on the long
  edge), so the user waited through the upload to get a raw provider 400.
  Resized through `dart:ui`, so no image package is needed, stepping the edge
  down until it fits, with the original as a fallback. The MIME type comes from
  the file's magic bytes rather than its extension, which is often wrong for a
  gallery photo.
- **The chat transcript is trimmed to the backend's budget.** The whole history
  was re-sent every turn with no limit while the budget was applied to the
  system prompt alone — so on Apple Intelligence (4,000 characters) or a 0.6B
  Qwen the answers quietly degraded after a few exchanges, and on a hosted
  provider every turn cost more than the last. Newest turns are kept, whole.
- **Leaving the chat actually stops the request.** A bare `await for` with no
  client meant switching tabs disposed the screen while the stream ran to
  completion: tokens kept arriving, a hosted provider kept billing, and the
  answer was still written to the history of a chat the user had walked away
  from. The subscription and an owned `http.Client` are now cancelled and
  closed in `dispose`.
- **SSE terminators are parsed, not string-matched.** `line == 'data: [DONE]'`
  missed `data:[DONE]` and any trailing whitespace — the space after the colon
  is optional in SSE — and the frame then fell through the prefix filter too,
  so the stream ended with no explicit terminator. Both copies now take
  `substring(5).trim()`, as `cloud_backend` already did.
- **One malformed entry no longer discards a whole model list.** `models.map((m)
  => m['name'] as String)` threw inside the `try` and returned `[]`, which the
  picker reports as "no models loaded — test the connection first".

### One formatter, one palette

Addressed 2026-10-18.

- **Sats formatting** was the same regex hand-rolled in a dozen places, and
  they disagreed: some kept the minus sign, some dropped it, so one number
  could appear two ways on two screens. All of them now call
  `SatConverter`, which gained `formatSatsSigned` (for deltas, where direction
  is the point) and `abbreviateSats` (for axis labels). One copy of the regex
  remains, in `SatConverter`.
- **Category colours** existed in three maps that disagreed — Shopping was
  purple in Analytics, blue-grey on the dashboard chart and grey in the CSV
  sheet — and none consulted the colour the user picked in Settings →
  Categories, which the `Categories` table has stored all along. One
  `CategoryPalette` now decides: the user's colour first, then the shipped
  colour for a seeded category, then a stable pick from a fallback set, so two
  custom categories are no longer both the same grey. The dashboard chart
  passes the user's colours through.
- `sat_amount_display.dart` (95 lines, never referenced) is deleted.

Both are covered by `formatting_test.dart`.

### The three oversized screens are split

Addressed 2026-10-18, as its own PR — pure moves, no behaviour change, so the
review question is only "is this the same code".

| file | was | now |
|---|---|---|
| `stack_screen.dart` | 1,157 | 327 + 5 files under `widgets/` |
| `onboarding_screen.dart` | 1,738 | 290 + 5 files under `pages/` |
| `settings_screen.dart` | 1,784 | 1,575 + `widgets/settings_widgets.dart` |

The moved classes were file-private, so each is public now with `super.key`
added. Two names had to change: `_LineChart` → `StackLineChart`, because
`fl_chart` exports a `LineChart` that the same file uses, and `_Period` →
`StackPeriod`, which had to move because the chart and the chips both need it.

Three real fixes went in alongside, each a few lines once the file was small
enough to see:

- The onboarding **Bitcoin server page now scrolls**. It was a fixed-height
  `Column` containing a text field, whose only slack was two `Spacer`s that
  clamp at zero, so on a small phone the keyboard overflowed it and could sit
  on top of the field.
- Settings **no longer rebuilds its whole tree per keystroke**. Two fields had
  `onChanged: (_) => setState(() {})`; each now drives a
  `ValueListenableBuilder` on its own controller, since the text decides
  exactly one widget in each case.
- `MonthCursor` replaces the triplicated month arithmetic.

Verified with `flutter build macos --debug` as well as the suite, since the
analyzer alone does not prove 2,900 moved lines still link.

### The last three P2 items

Addressed 2026-10-18.

- **Streaming bodies have an idle timeout.** Every backend applied its timeout
  to `client.send(...)`, which completes as soon as the response *headers*
  arrive — so a body that stalled afterwards stalled forever. A dropped mobile
  connection mid-answer left the chat spinner turning with no error, and the
  import's cancel flag is only checked when a token arrives, so that hung too.
  The new `Stream.idleTimeout` extension measures the gap between events
  rather than a total budget, because a long answer is not a broken one: 45s
  for a hosted provider, 120s for a self-hosted or on-device model.
- **On-device generation is serialised per channel.**
  `EventChannel.receiveBroadcastStream` installs one handler per channel name,
  so a second concurrent listen *replaces* the first — which then receives
  nothing and never completes. Reachable without trying: the dashboard's
  monthly insight generating on Apple Intelligence while the user opens the AI
  tab and asks a question. Multiplexing would need request ids on both native
  sides; `serialisedOnChannel` queues instead, and a queued answer beats a hung
  one. Both on-device backends also gained a 90s idle timeout, since nothing
  else would ever end a stream the native side had abandoned.

  **Narrowed 2026-10-18.** This fixes the *Dart* side only, and the claim that
  `stream_resilience_test.dart` proves it is too strong: that test runs under
  `flutter test`, which has no engine, so it exercises the queue and nothing
  else. The queue slot is released when the Dart subscription is cancelled, not
  when the native side actually stops — and neither bridge stops on cancel
  (`GeminiNanoBridge.kt:132`, `FoundationModelsBridge.swift:184`), so an
  abandoned generation's trailing deltas can still land in the next answer's
  stream. See `TODO.md` item 2.
- **The router's redirect no longer reads the database.** It queried
  `app_settings` for the onboarding flag on every navigation — each bottom-nav
  tap, each `context.push`, and again on each of GoRouter's
  redirect-resolution passes — so a tab switch waited on a round-trip. It is
  synchronous now against `onboardingCompleteNotifier`, read once at startup,
  kept current by the three places that change it (finishing onboarding,
  resetting onboarding, resetting all data) and included in
  `refreshListenable` so a change still re-runs the redirect immediately.

Covered by `stream_resilience_test.dart`: that a quiet stream fails, that a
slow-but-alive one does not, that a second generation waits rather than
clobbering the first, that a failure does not block the next, and that
different channels do not queue behind each other.

### Currency is converted, not mixed

Addressed 2026-10-19, after the second review pass found the first fix only
covered the write side.

- **Every aggregate summed `amountFiat` across currencies.** `fiatCurrency` was
  written by four paths and read in exactly one place — a row label — so the
  dashboard, budget progress, analytics, year-to-date and the exported summary
  all added dollars to pounds under a `£` label, while the transactions list
  showed each row correctly. `FxRates` now converts each row into the display
  currency first, using BTC as the bridge because it is the one rate table the
  app already holds for every currency. Same-currency rows — nearly all of them
  — are returned exact and need no rate at all, so this works offline.
  **It applies today's cross rate to every row**, so a March USD charge is
  converted at October's rate: a deliberate trade, since major cross rates move
  a few percent a year against the 20–30% error of adding them, and it stays
  synchronous. A row with no rate is excluded from the fiat totals but keeps
  its sats in the stack, and the dashboard says how many rather than showing a
  quietly smaller number. Recent rows are taken from the originals, since they
  are rendered with their own currency label.
- **The live edit path rewrote historical values.** An earlier entry here said
  "an edit now rewrites `fiatCurrency`", crediting `AddTransactionSheet`'s
  editing branch — but that branch was **unreachable**: its only call site is
  the add path. The real edit path, `TransactionEditSheet`, derived both columns
  from `priceNotifier` — the price *now*, in the *active* currency — and stored
  the row's *old* code. So editing only the category of a March purchase
  rewrote its sats at October's price, and a USD row edited in GBP got a
  GBP-derived figure labelled `$`. It now keeps the row's currency (the field is
  pre-filled in it) and preserves the rate the transaction actually happened
  at; changing the amount scales both columns at that rate. The dead branch is
  deleted.

Covered by `fx_rates_test.dart` and `currency_aggregates_test.dart`, end to end
through the real services.

### Light mode is legible

Addressed 2026-10-19. Not hardcoded dark colours — the earlier light-mode pass
found all of those. These were colours tuned for dark and reused on light, so
nothing looked wrong in the code.

- **Secondary text was one grey for both themes**: `#888780`, 5.39:1 on the
  dark background but **3.37:1** on the light one, at 10–11px, across 125 call
  sites — every caption, metric label, date header and category name. No single
  grey can serve both: the luminance a colour needs to clear 4.5:1 against
  near-black and near-white do not overlap. It is two values now, resolved from
  the theme through `context.textSecondary`; the light one, `#67665F`, is the
  lightest warm grey that clears AA on the background, on white cards *and* on
  the tinted `surfaceContainerHighest` (`#6F6E67` clears the first two and fails
  the third).
- **Bitcoin orange as text was 2.30:1** on a light card — the sats figure on
  every transaction row and spending bar, the app-bar price. Text now uses
  `context.bitcoinOrangeText` (`#9A5600` on light, 5.67:1); fills, borders and
  icons keep the brand colour, since only small text needed it.
- **Banner copy was set in its own accent over a tint of that accent**, measured
  at 1.97–2.20:1 — the least readable text in the app was the Settings banner
  explaining which third parties can see your Bitcoin addresses. Body copy and
  route rows move to theme text; headings and one-line banners keep their
  semantic colour through `context.legibleAccent`, which darkens an accent just
  enough to clear AA on its own tint. It is computed rather than hand-picked,
  because each accent needs a different amount.

  **The first version of that helper was wrong**, and only measuring caught it:
  it checked against an 8% tint over pure white, and the colours it produced
  then failed at 4.19–4.44:1 on the off-white scaffold the banners actually sit
  on. It now measures against the darkest real case (12% over the scaffold),
  which clears all eight real combinations at ≥4.65:1.

Also fixed in passing: the add-transaction amount toggle was labelled **"USD"**
whatever the user's currency was. `contrast_test.dart` pins all of the above
against the real theme through a widget, including that each raw colour does
fail — so the tests show the bug as well as the fix.

### Tabs keep their state

Addressed 2026-10-19.

- **Every tab switch destroyed the screen.** The shell was a plain
  `ShellRoute`, which builds a different child *type* per tab, so the element
  tree could not reconcile and each switch discarded the screen's State. Set a
  filter and a search on Transactions, tap Dashboard, tap back: both were gone,
  the scroll position was lost, and the whole table was re-queried behind a
  full-screen spinner. The same happened to the Stack period and DCA input and
  the selected month on Budgets, and the Dashboard re-ran its insight reads on
  every visit. It is a `StatefulShellRoute.indexedStack` now — one branch per
  tab, kept alive, built lazily on first visit. The AI branch is last so a
  branch index always equals its nav-bar index even while AI is hidden.
- **Keeping tabs alive exposed one screen that depended on dying.** The AI chat
  loaded its configuration once in `initState`, and tab-switching had been
  quietly re-running it on each visit — so with tabs kept alive, fixing an
  Ollama URL in Settings and returning would leave the chat reporting the old
  URL as unreachable. `OllamaService.configChanges` is bumped on every AI
  configuration write, and the chat re-initialises when its
  `configFingerprint` changes — which deliberately excludes the selected model,
  so picking a model from the chat's own dropdown does not reload the chat. The
  other four tabs are stream-driven and stay correct while alive.

`tab_state_test.dart` drives the real `AppShell` with tabs that hold state.
Before relying on it, the same scenario was run against the old `ShellRoute`
in a throwaway test: the counter came back as **0**, so the new test does
distinguish the two designs. Verified with `flutter build macos`; not yet
exercised by hand in the running app.

### The import consent gate has a way out

Addressed 2026-10-19.

- **Consent was permanent, silent and unrevocable.** One "Send to Anthropic"
  tap was written to settings at the tap and never asked about again; there
  was no revoke control anywhere, and nothing afterwards said an upload had
  happened. Settings → Servers now has a **Statement imports** row that names
  every provider allowed to read imports and withdraws them in one tap, and is
  shown even when none is, so the answer is visible somewhere other than the
  dialog that asked. The preview says **"This file was sent to … to be read"**
  whenever an off-device tier ran — including when it found nothing and the
  local rules took over, since the upload happened either way.
- **The preview said "Parsed via Ollama AI" for every provider.** It names the
  provider that actually read the file.
- **A yes was remembered even if the import was then cancelled.** It is now
  held for the length of the import and stored only once the import completes.
- **The dialog promised a local fallback to photos**, which have none. The copy
  is now per flow, and both say that a yes covers later imports and where to
  withdraw it. `AiPrivacyDisclosure` names statement imports among the things
  that send data, instead of implying everything is per-request.
- **The five-minute timeout kept running behind the dialog**, so it could fire
  and stack a second dialog over the first. It is paused while the question is
  up and restarted afterwards.
- **`isLocalEndpoint` failed open.** `Uri.parse('ollama.example.com:11434')`
  reads the host as a *scheme* and yields no host at all, which the check
  called local: no consent prompt, auto-insight on, and a false privacy claim
  for a remote server. It now fails **closed** for anything non-blank without a
  host, and the Ollama, LM Studio and Maple URLs are normalised on save and on
  load through `normalizeServerUrl` — the same rules `XpubService` already
  used, now shared — so a bare `host:port` gains its scheme (http for the two
  self-hosted servers) and Settings shows the URL actually saved.
- **Photo import asked for consent before checking the backend could see**,
  and swallowed the `InferenceException` saying why it could not. The
  capability is checked before a photo is even picked, and again in the
  service before consent; a backend error reaches the preview in its own words.

Covered by `import_consent_test.dart`, end to end through `importFile` and
`importImage` with a fake hosted backend, and by `ai_privacy_test.dart`.

### Parsing conventions are decided per file

Addressed 2026-10-19.

- **Dot-grouped thousands.** The comma had a three-digit grouping rule and the
  dot had none, so a German `2.500` became **2.5** — a 1000× understatement
  with nothing to show for it — and `1.234.567` dropped the row. A blanket
  mirror rule would turn a BTC export's `0.125` into 125, so this is inferred
  the way `_inferDayFirst` is: `_inferDotGrouping` votes over the file's own
  amounts (`12,50` and `1.234,56` for, `12.50` and `0.12345678` against), and
  a file with no decisive value keeps the decimal reading. Two or more dot
  groups can only be grouping and are always read so.
- **`_inferDayFirst` took the first decisive date**, so one US row at the top of
  a merged UK export decided the file. It is a vote now; each row's own
  decisive component still overrides the file's answer for that row.
- **The PDF heuristic tier had none of the date work** — the tier a user lands
  on after declining off-device consent. It read every date month-first, had
  no dotted pattern (a German `01.02.2025` line matched nothing), and its
  amount pattern knew only `1,234.56`, and matched `2.500` as `2.50`. It now
  infers day order and amount convention from the whole text, and matches
  `/`, `-` and `.` dates and both amount conventions.
- **The delimiter was sniffed from the first line**, which in many exports is a
  title or account summary. It is now the delimiter that splits the most of
  the first twenty lines into the same number of fields. The rules tier also
  looks for the header row among the first fifteen rows, instead of assuming
  row 0, so those exports no longer fall through to manual mapping.
- **Only `\r\n` was normalised**, so a classic `\r`-only export was one row.

Covered by `parsing_conventions_test.dart`. Run against the previous parser,
eight of its ten tests fail; the two that pass are the guards that a BTC-style
decimal is *not* reinterpreted.

### Accessibility

Addressed 2026-10-19.

- **There was no `Semantics` anywhere in the UI layer**, and most small controls
  were a `GestureDetector` around a decoration: unlabelled or invisible to a
  screen reader, unreachable from the keyboard on desktop, and 14–24px tall.
  They now go through `Tappable`, which keeps the decoration and adds a
  button node with a name and selected/toggled state, a 48×48 target
  (Android's floor and Material's `kMinInteractiveDimension`; iOS asks for
  44), keyboard focus with a visible ring, Enter/Space activation and a
  pointer cursor. Swatches are named by colour (`colourName`), icon choices by
  name, and the price chip reads "Bitcoin price $67,000, updated 2 minutes
  ago" rather than "2m". Long-press-only actions (budget options, copying a
  chat message) carry a spoken hint. The three charts expose a spoken summary.
- **Three month selectors**, two of them bare 20–22px icons. One shared
  `MonthSelector` of `IconButton`s with tooltips, a live-region month label,
  and `FittedBox` so it scales down in a narrow app bar at large text sizes
  rather than overflowing.
- **Large text overflowed.** The trailing amount column in the transaction row,
  the dashboard wallet row and the spending bar took whatever width its text
  wanted, so at 2× the row overflowed — by 336px at 3× on a 360px screen.
  `ShrinkToFit` caps it and scales it down; amounts shrink rather than being
  ellipsised. The spending bar's 100px category label now follows the text
  size, capped at a third of the row.

Fixed in passing: more orange-as-text and category-colour-as-text sites the
contrast pass missed (Repeat, the period chips, the wallet type badge, BTC
transaction names), and `TransactionListItem`'s private currency-symbol table,
which duplicated `CurrencyUtils` and printed amounts without grouping.

`accessibility_test.dart` uses Flutter's own `androidTapTargetGuideline`,
`iOSTapTargetGuideline` and `labeledTapTargetGuideline`. Its first version
passed against the row that overflowed: it faked the screen width with a
`MediaQuery`, which changes what widgets read but not the constraints they lay
out in. It sets the test view now, and fails against the old row at 2× and
3×. Not yet checked with VoiceOver or TalkBack on a device.

### The smaller correctness items

Addressed 2026-10-20 (`TODO.md` item 9).

- **Two categories could share a name** (schema v8). Transactions, budget
  progress, imports and learned mappings all key on the *name*, so a pair was
  indistinguishable: a rename rewrote both, one read zero spend forever, and
  neither could be deleted. `Categories.name` now has a unique index, and the
  service rejects a clash — case-insensitively, which is stricter than the
  index — with a message on the name field instead of a raw SQLite error.
  `migrateToV8` **renames** existing duplicates ("Pets (2)") rather than
  deleting them, unlike v6 and v7, because a category has budgets pointing at
  its id; the transactions stay with the oldest, since they were matched by
  name and there was never a way to tell whose they were.
- **The same xpub in two wallets synced the second to nothing** while
  reporting every row as skipped: the dedupe looked at every wallet's hashes,
  and the hash was salted with the txid alone. The scan now dedupes against
  its own wallet, and the hash is scoped with `HashUtils.scopedToWallet` —
  derived from the stored hash rather than added to the salt, because a row
  keeps only eight characters of its txid. That let `migrateToV8` rescope
  every stored xpub row in place: a delete-and-resync would have dropped every
  category and note the user had set on them. `XpubService` takes an optional
  HTTP client, so the sync is now tested end to end against a fake chain.
- **A failed restore left the database closed** for the rest of the session,
  so every later query threw, and a copy that stopped partway left a torn file
  for the next launch. `replaceDatabaseFile` copies the original back over a
  failed copy, and every outcome now ends at a dialog that can only be left by
  quitting — the database cannot be reopened under the running services.
- **Today's BTC price was cached permanently** on first request, so anything
  dated today kept that mid-day quote for good. Only a settled day — more than
  two days old, since the key is a local date and the sources bucket by UTC —
  goes into the permanent cache; an unsettled day is cached in memory for 15
  minutes, so one import still fetches it once. A mid-day row an earlier build
  wrote for an unsettled day is deleted rather than later served as final.
  Rows such builds wrote for days that have since settled cannot be told
  apart, and are left.
- **"Imported" counted rows recorded against the source, not the ledger**, so
  importing a statement under a second source reported every row while the
  Transactions screen gained nothing. Both inserts use
  `insertReturningOrNull`, which says whether a row was written (`insert`
  with insertOrIgnore returns a rowid either way), and the summary reports
  rows already in the ledger separately and says why.
- **The Stack screen walked every transaction four times per BTC price
  tick**, through getters on its content widget. `StackStats` does it in one
  pass when the rows change, and recomputes when the calendar month turns.
- **The Dashboard rebuilt every section and every row on each price poll**:
  its price and currency listeners wrapped the whole content. Each section
  that shows a price-derived figure now listens for itself, and a
  transaction row with stored sats — almost all of them — does not listen at
  all.
- **Four Stack widgets read `app.currencyNotifier.value` in `build`** without
  subscribing, kept correct only by a parent listener that discarded the value.
  They take the currency as a parameter now, and no longer import `main.dart`.
- **`setState` after an await without a `mounted` check**: two date pickers,
  and the two import entry points, which are only ever called straight after
  a picker returns and so ran `setState` first thing on a possibly closed
  screen.
- **Insight failures were silent.** A tap on Generate with an unreachable
  server or a rejected key did nothing visible, dropping the readable message
  `CloudBackend.describeError` builds. A tap now says why; the automatic
  refresh stays quiet. An empty answer is an error rather than being cached as
  the month's insight.
- Tidied: `SetGoalSheetState` is private, and the constructors with
  `super.key,required` crammed on one line are formatted.

Found while testing: the Dashboard's section header ("Spending Breakdown …
View Analytics") overflowed at large text sizes — the same bug as the
transaction row, in a header the accessibility pass missed. Its title gives
way now.

`dashboard_rebuild_test.dart` is the first test to pump a whole screen against
real services on an in-memory database. It measures rebuild scope by widget
identity — a row whose parent did not rebuild keeps the same widget object —
and fails against the old structure. The other fixes are covered in
`schema_integrity_test.dart`, `xpub_service_test.dart`,
`database_restore_test.dart`, `btc_price_service_test.dart`,
`import_service_test.dart`, `stack_stats_test.dart` and `insight_test.dart`;
the xpub test was also run against the old sync, which gives the second wallet
0 rows. The restore dialog and the insight snackbar were not exercised by hand.

### CI, lints and docs

Addressed 2026-10-20 (`TODO.md` item 10), in two PRs: a format-only one, so
nothing else had to be read through 7,000 lines of re-indentation, and this.

- **Android did not build at all** on the pinned Flutter 3.47.2. It now
  refuses Gradle below 8.14, AGP below 8.11.1 and Kotlin below 2.2.20, and the
  project was on 8.11.1 / 8.9.1 / 2.1.0. Nothing noticed, because CI built
  nothing native. Raised to exactly those floors; Flutter already warns that
  Gradle 9.1, AGP 9.0.1 and Kotlin 2.3.20 are next (`TODO.md`).
- **CI compiled nothing native.** It now also checks `dart format`, resolves
  with `--enforce-lockfile`, builds a debug APK on ubuntu, and builds iOS
  (unsigned) and macOS in parallel on a Mac runner — the cheapest checks that
  reach the manifest merge, the Podfiles, the entitlements and both native AI
  bridges. The Android build above is what it would have caught.
- **`claude.yml` ran for anyone** who wrote "@claude" on this public repo. It
  now requires an owner, member or collaborator, and queues per issue rather
  than running in parallel. The review workflow cancels a superseded run, and
  skips drafts and fork PRs (which run without the secret and could only
  fail).
- **No lint rules were enabled.** `flutter_lints` is on 6.0.0, and the rules
  added are the ones that catch bug classes this code has had —
  `unawaited_futures`, `cancel_subscriptions`, `close_sinks`,
  `avoid_void_async`, `only_throw_errors` — plus conventions it already
  follows. `close_sinks` found a real leak: a failed Electrum handshake never
  closed its socket. `require_trailing_commas` is deliberately off: from
  language 3.7 the formatter owns trailing commas. `avoid_dynamic_calls` (43
  sites) and `discarded_futures` (47) are recorded as not enabled, with why.
- **The onboarding screen's first privacy claim was false**: "an encrypted
  SQLite database … Nothing leaves." The database is plain SQLite, and a
  wallet sync sends addresses to a block explorer. It now says what is true;
  the README's privacy section is rewritten the same way and lists what
  leaves the device and when. Real encryption is a decision in `TODO.md`.
- **Android declared CAMERA and READ_MEDIA_IMAGES.** The audit's version of
  this was wrong — `image_picker` *does* request CAMERA at runtime when the
  manifest declares it, so nothing crashed. But neither is needed: the capture
  intent and the system photo picker work without them, declaring CAMERA only
  added a prompt, and Google Play's photo-permission policy rejects
  READ_MEDIA_IMAGES for occasional picking. Both removed; the merged manifest
  of a real build confirms neither comes back from a plugin.
- `ITSAppUsesNonExemptEncryption` is `false` in both Apple Info.plists, with
  the reasoning beside it, so uploads stop asking.
- `dedup_hash_test.dart` now also runs the real import and recurring call
  sites and checks what they stored, including two series started the same
  day; the xpub call site is covered in `xpub_service_test.dart`.
- `SatsStackNotes.md` is deleted: four of its five items had shipped, and the
  fifth (a tab roadmap) is now in `TODO.md`. The README's stale lines are
  fixed, as is the "Add xpub wallet" tooltip. `CLAUDE.md` is gitignored, so its
  corrections (SDK, pins, schema notes, Podfile, Info.plist rationale) are
  local.

`flutter build apk --debug`, `flutter build ios --debug --no-codesign` and
`flutter build macos --debug` were run locally before the workflow was
pushed; the workflow itself is proven only by its first run on the PR.

### The macOS model build phase, and cancelling on-device answers

Addressed 2026-10-20 (`TODO.md` items 1, in part, and 2).

- **The LiteRT-LM build phase swallowed every failure.** Each
  `install_name_tool` and `codesign` ended in `2>/dev/null || true`. With
  those removed, the very first build failed: `libLiteRtTopKMetalSampler`
  does not exist in this flutter_gemma version, and every earlier build had
  printed a warning about it and carried on. It turns out to be optional —
  LiteRT loads it if present and samples on the CPU without it — so it is now
  skipped by name, while the two libraries LiteRT cannot run without fail the
  build if missing.
- **The copied frameworks were always signed ad hoc**, which library
  validation refuses to load into a Developer ID-signed app and notarization
  rejects. They are now signed with the identity Xcode is signing the app
  with (`EXPANDED_CODE_SIGN_IDENTITY`), with the hardened runtime and a
  timestamp when that is a real identity. No
  `disable-library-validation` entitlement is needed: same-team code loads.
- **Architecture.** LiteRT-LM ships arm64 only. The phase now skips an
  arm64-less build instead of failing, and still installs for a universal
  one. More importantly, `LocalModelChoice.runsHere` checked the OS rather
  than the CPU — its comment said "Apple silicon (not Intel)" while the code
  said any Mac — so an Intel Mac, or a 32-bit or x86 Android device, was
  offered a multi-gigabyte download that could never load. It checks the ABI
  now.
- **The product name was the template's**, so the window title read
  `sats_stack`. It is "Sats Stack"; the bundle id is a separate decision
  (`TODO.md` item 1), because changing it moves the sandboxed data.
- **Cancelling an on-device answer broke the next one.** Reproduced first, on
  this Mac: an answer requested straight after a cancelled one arrived
  **empty**. The cancelled Swift task unwound by throwing
  `CancellationError`, which the catch reported as `generation_failed`, then
  sent end-of-stream through a sink that by then belonged to the next request.
  Both bridges now give each generation a token and drop any emission whose
  token is no longer current — checked on the main thread, where `onCancel`
  runs, so the two cannot race — treat cancellation as cancellation, and make
  a new generation wait for the cancelled one to unwind. This also retires the
  narrowed claim about `serialisedOnChannel`: its queue slot is released on
  cancel, and the native side now waits for itself.

  The TODO's account of the Kotlin side was partly wrong: `collect` does
  suspend between chunks, so cancelling the job did stop it. The real faults
  were the same two as Swift's — cancellation reported as failure, and no
  wait before the next request.

`integration_test/apple_intelligence_test.dart` gained the cancel-then-ask
case; it fails against the old bridge and passes against the new one on macOS
(three runs) and on the iOS 27 simulator. The Kotlin bridge compiles cleanly
but is **not verified on a device** — Gemini Nano needs AICore on a physical
phone. The renamed app also passes the native macOS `RunnerTests`, whose test
host had the old name hardcoded.

### The downloadable-model backend is removed, and macOS has its real id

Decided 2026-10-20 (`TODO.md` item 1's two decisions).

- **`flutter_gemma` is gone.** Both it and `flutter_gemma_litertlm` are
  discontinued, and the backend they powered was the only one of six with an
  unmaintained native dependency, a hand-written Xcode build phase and
  multi-gigabyte downloads. Removed with it: the backend, its Settings
  section and onboarding card, the memory and storage probes that existed only
  to size its catalogue (and their native channels on iOS and Android), the
  macOS LiteRT build phase, and a dozen transitive packages. Apple
  Intelligence, Gemini Nano, the self-hosted and the hosted backends remain.
  iOS goes back to a 15.0 minimum — the floor flutter_gemma had raised.
- **Nobody who used it is stranded.** A stored choice of it moves to the
  platform's built-in on-device model — Apple Intelligence or Gemini Nano —
  rather than falling back to Ollama, which on a phone means no AI tab, and
  never to anything hosted. Its model setting is deleted.
- **Its weights are deleted.** They were 0.6–5 GB each, and with the backend
  gone no screen could remove them. `RemovedModelCleanup` deletes them at
  launch, by exact file name (and their partial downloads) in Documents, and
  the package's own folder in Application Support on macOS. The database
  lives in the same Documents folder, so a test pins that it, its backup and
  an unrelated file with the same extension all survive.
- **macOS uses `app.satsstack.SatsStack`**, matching iOS, instead of the
  template's `com.satsstack.satsStack`. The app is sandboxed, so a new id is a
  new, empty container; the old data is untouched where it was, and the
  README gives the export/import steps and the one-line copy. API keys do not
  come across and have to be re-entered.

Covered by `removed_local_model_test.dart`. All three platforms build; the
Apple Intelligence integration test passes on macOS under the new id, and the
container appears where the README says it will.

### Android no longer backs up the database or the API keys

Addressed 2026-10-20; found while writing the encryption plan.

The manifest set no backup rules, so Android Auto Backup was on with its
defaults. **The plaintext database went to the user's Google Drive.** The API
keys went with it, in `flutter_secure_storage`'s EncryptedSharedPreferences,
but the Keystore master key that decrypts them never leaves the device, so on a
restored phone they could not be read.

`data_extraction_rules.xml` (Android 12+) now keeps both out of cloud backup,
and keeps the keys out of device-to-device transfer, which cannot move a
Keystore key either. `backup_rules.xml` (Android 8–11) cannot tell the two
apart, so it excludes both everywhere. Moving to a new phone is Settings →
Data → Export and Import.

Checked by building the APK and dumping the compiled rule files and the merged
manifest. **Not exercised with `bmgr` on a device** — that needs an emulator
with a backup transport, and the rules are declarative.

### Test gaps

The suite went from 102 tests to 209 over this work. Month boundaries, category
renames, the AI-tab rule, the migrations, the categoriser, the price map, the
dedup hash's wallet scoping, the formatters and the stream guards are all
covered. What is still missing is listed in [`TODO.md`](TODO.md) item 13.

---

## Third pass — 2026-10-21

Seven parallel reviews (import, data layer, Bitcoin, AI, UI, native/CI/docs,
tests and dead code), a live run on the iOS simulator, and a check of each
finding against the code before it was fixed. About 180 findings; the ones
below are fixed, each with a test that fails on the old code unless noted.
What is still open is in [`TODO.md`](TODO.md) item 15.

**Status:** merged as PRs #22–#28 (docs #29).

### Screens that broke outright — #22
- Both ways of deleting a transaction were broken: the confirmation dialogs
  popped with the row's or the sheet's context, which sits in the tab's
  navigator while the dialog is on the root one. Long-press → Delete popped
  the tab's only page (a blank app in release); the edit sheet's Delete closed
  the sheet and deleted nothing.
- The Bitcoin server onboarding page rendered blank on every device: Spacers
  in a scroll view throw in layout. The other text pages overflowed rather than
  scrolling on a small phone or at large text. All four share
  `OnboardingPageFrame` now.
- Bottom sheets opened inside the tab, so the tab bar stayed live behind them.
  They open on the root navigator; the budget options sheet, which would then
  have popped the Budgets tab, pops itself.
- Settings' server test hung forever on a URL with no scheme (`ArgumentError`
  is not an `Exception`).

### Import money — #23
- Swan, Coinbase and Strike profiles booked a fiat column in the account's
  currency: $500 into a BTC account was 500 BTC. Profiles now say what their
  amount column is in.
- A non-display-currency account's sats used the display currency's price.
- Amex-style cards (charges positive) became all income; `CR`-marked UK
  statements all spending; a PDF with a running balance read every salary as
  spending, and a "CREDIT INTEREST" line flipped the rest of it.
- A same-day refund, or a second identical row, was dropped as a duplicate;
  the same charge in two accounts kept one row. Hashes now carry the row's
  occurrence in the file and are scoped to the source, not the one shared
  wallet. **Behaviour change:** the same statement imported under two sources
  is now two visible copies rather than one.
- The Wells Fargo profile never matched a real export, and skipped its first
  row.

### AI: what it is sent, and the disclosures — #24
- The prompt hardcoded `$`/USD, rounded every figure, sent a missing price as
  `$0` and named no month: a GBP user's £12.50 came back as "-$13".
- Every chat question was sent twice.
- Import consent for Ollama, LM Studio and Maple carried over to a different
  server; the Dashboard insight card's recipient went stale after a provider
  switch; Settings kept saying "nothing leaves" after a public URL was saved;
  onboarding and the chat sheet judged self-hosted privacy by provider, not
  URL; the chat sheet offered an "Apple Intelligence URL".

### Data that could be lost or locked — #25
- The schema upgrade had no transaction: killed partway through v8, the
  database could never be opened again ("index already exists").
- An xpub row's hash came from a local time with no offset, so a timezone
  change made the next sync delete and re-add every row, losing each category
  and note. Hashes are UTC now, and rows under an older hash are re-keyed in
  place.

### UI that showed or saved the wrong thing — #26
- Budgets rounded each figure on its own ("£13 spent, £88 remaining").
- A decimal comma was dropped or read as grouping ("4,50" → 450).
- "Add budget" could replace an existing one; delete did not confirm.
- The System theme came back as Dark; an unpriced Bitcoin send showed as a
  green "+".
- Re-running onboarding wrote defaults over the real settings — including
  switching a self-hosted Esplora server back to mempool.space; Reset left
  most in-memory state behind; "Show BTC price: off" promised no price
  requests, which was never true.

### AI setup and errors — #27
- A self-hosted server could never pass its first connection test: no model
  meant "unavailable", and models were only listed once available.
- Server errors before and during an answer were dropped or reduced to a
  status code; a half-answer was saved as complete; the offline screen gave
  server advice to every backend. A hosted answer lost its last frame without
  a trailing newline.

### Light mode — #28
- White on Bitcoin orange is 2.4:1, on every filled button, the FABs and the
  hero card; text buttons were 2.3:1; the status bar was white on light;
  several accents were 1.5–2.1:1 as small text.

### Claims in this file that were wrong

- **"The last 999 ms of the month fall into no month."** Drift stores
  `DateTime` as whole seconds (there is no `build.yaml`), so a saved row never
  had sub-second precision; the half-open `DateRange` is still right, but the
  `month_boundary_test` aggregate group cannot fail against the old code.
- **"One palette"** — Analytics still ignores user colours, and its seeded
  colours disagree with the database seed.
- **"Streams are built once"** — `CategoriesSheet` still builds one in
  `build()`.
- **48 px tap targets** — the category icon grid's cells are 33 px.
- **"The only dead code is item 11's"**, and **`scripthash_test` covers
  `ElectrumService`** — it tests a helper defined inside itself.
- **The Wells Fargo `skipHeaderRow` fix** was never applied to the profile.

## Working through item 15 — from 2026-10-29

Item 15's open list, fixed one PR at a time, in the order `TODO.md` gave.

### xpub wallets can be re-synced and removed
- `ManageWalletsSheet` was the app's only re-sync UI and nothing opened it, so
  a wallet was never refreshed after it was added. The Transactions tab's
  wallet button now opens it (adding a wallet is one tap further, from the
  sheet). Each wallet can be removed, which deletes its rows after a
  confirmation that names how many.
- Re-adding a tracked key doubled the stack, because rows are hashed per
  wallet. `addXpubWallet` refuses a key already tracked and points at Rescan;
  the key is stored trimmed so the check can match.
- A failed first sync left an empty wallet (it is created before the sync),
  which the duplicate check would then have blocked a retry on. The sheet
  removes it again.

### Recurring series have a stable id (schema v9)
- A series was identified by its period, anchor, description and amount, so
  editing an instance split it off and the original regenerated: duplicate
  rows. Renaming the anchor recreated nearly every past instance. Rows now
  carry `recurringSeriesId`, random when a series is started, and the
  generation cursor is keyed on it.
- The dedup hash of a generated instance is built from the series id and the
  due date only (`TransactionService.recurringDedupHash`); it used to include
  the description and amount, so an edit changed it.
- With a stable id the cursor is authoritative. It used to be overridden for a
  series that looked re-created, which made deleting every instance but the
  anchor regenerate them all.
- A series can be stopped: Stop repeating in the edit sheet turns its rows into
  one-offs and drops the cursor. There was no way to do this.
- Each instance is priced on its own date (`priceAt`, wired to
  `getHistoricalPrice` at launch): a fiat series keeps its fiat and gets that
  day's sats, a Bitcoin one the reverse, falling back to the newest instance's
  figures when there is no price. Every instance used to copy the anchor's
  sats. Generated rows also keep `isBitcoin`, which they used to lose.
- Existing series are adopted by the v9 migration — grouped the way the old key
  grouped them, and also by wallet, so two identical series in two accounts are
  no longer one (TODO item 10). Each keeps its cursor.

### Budgets have a currency, and alerts are sent once per occasion
- A budget was a bare number, read in whatever the display currency was, so
  switching GBP → USD turned £500 into $500 and could fire an overspend
  alert. `budgets.currency` (schema v10; existing budgets stamped with the
  display currency) and `BudgetProgress.limitFiat`, the budget converted into
  the display currency, which progress, "left", the totals, the alerts and
  the exported summary all read. With no rate to convert it, the card shows it
  in its own currency and it is never reported as overspent.
- Alert dedupe was a per-session set of ids: every cold start re-sent every
  alert (the stack goal on every launch once reached), and a new month could
  not alert until a restart, because the id had no month in it. Alerts are
  now claimed in `AppSettings` by `NotificationLedger`, keyed per category per
  month and per goal amount; budget keys from other months are pruned.

### xpub keys are scanned for the right addresses, and unpriced rows heal
- An `xpub` exported for a SegWit account (Ledger, Trezor and others do this)
  was scanned as legacy and looked empty. Adding a mainnet `xpub` now probes
  its first 20 receive addresses as native SegWit, nested SegWit and legacy,
  and stores the key re-encoded for the type that has history
  (`XpubService.withFormat`), so every later sync derives the right ones.
- Testnet keys were accepted, scanned against a mainnet server and priced as
  real BTC. The form and `syncWallet` refuse them.
- A row whose day had no price was stored with a fiat value of 0 and never
  priced again. Each sync now re-prices kept rows at 0, and reports how many
  are still unpriced (`XpubSyncResult.unpricedNote`), naming a self-hosted
  Esplora server — which has no price endpoint — as the likely cause. That
  used to give no prices at all without a word.

### The dashboard's figures
- The "not yet in these totals" note counted unconverted rows across all
  history, so one old foreign-currency import kept it on every month. It counts
  the month on screen.
- The spending breakdown (dashboard bars, Analytics legend) rounded each figure
  to whole units on its own: £12.50 read £13. Each list now uses one precision,
  with pence if any figure has them.

### The monospaced font is a font
- `assets/fonts/RobotoMono-*.ttf` had been GitHub HTML pages since the first
  commit, so every figure set in `AppTextStyles.mono*` fell back to the system
  font and ~600 KB of HTML shipped in the bundle. They are the static TTFs from
  `googlefonts/RobotoMono` now, with the Medium face declared as weight 500.
- Roboto Mono is under the SIL Open Font License (not Apache 2.0, as this file
  used to say), which must accompany it: `assets/fonts/OFL.txt` is bundled,
  registered with `LicenseRegistry`, and Settings → About → Licences shows it.

### Import: cancelling, and the column mapper
- The cancel flag, the consent answers and the "was it uploaded" flag lived
  on the `ImportService` singleton, so starting an import reset the previous
  one's: an import cancelled while its consent dialog was up, answered yes a
  moment later, carried on and uploaded. Each import now runs in a zone with
  its own `_ImportRun`, cancelled through its own `ImportCancelToken`; a
  consent answered after a cancel is refused before anything is sent.
- Leaving the import screen did not cancel. It cancels its token on dispose.
- The column mapper took row 0 as the header, so an export opening with a
  title showed the title as column names and read the mapping against the
  wrong rows. The mapper and `parseWithMapping` both start from the detected
  header row.
- Dates overflowed rather than being rejected: `DateTime` and
  `DateTime.tryParse` normalise, so 25/12/2025 read as MM/DD became 2027 and
  31 February became 3 March, in the mapper and the guessing parser alike.
  `_calendarDate` rejects a date that does not exist. The mapper's formats
  accept `/`, `-` and `.`; DD/MM/YY is offered; and a column with a first part
  over 12 is detected as day-first.

### Import: which tier reads it, and what is remembered
- On-device AI was never used for an import: readiness required a selected
  model, and Apple Intelligence and Gemini Nano have none by design.
- A PDF the AI could not read came back empty without trying the heuristic
  reader, which is what runs when there is no AI at all. It is tried now.
- A file over 100,000 characters was cut for the AI without a word, so a long
  statement lost its later rows silently. `ImportResult.aiInputTruncatedAt`
  says how much was sent, and the preview says so.
- The column mapper saved its layout before parsing, so a layout that read
  nothing was tried first on every later import, with no way to remove it. It
  is saved only after it reads something, and a source's menu has "Forget
  saved column layout". The mapper's parse also skipped the learned
  categories; `prepareForReview` applies them on every path.
- Learned categories were keyed on the description as edited in the preview,
  which no later file contains. They are keyed on the file's own description
  (old mappings still match).
- The keyword categoriser uses the seeded category names, so renaming "Food &
  Dining" to "Food" filed matches under a name that no longer existed.
  `CategoryService` records each rename of a built-in category
  (`system_category_name:<seeded name>`), and imports use the current name.

### Import: pricing, and the smaller misreadings
- Historical prices were fetched one day per second, serially, behind a bare
  spinner — five minutes for a year of statement. `prefetchHistoricalPrices`
  takes a Mempool server's whole price history for the currency in one
  request when five or more days are uncached, and caches each day's nearest
  point; the per-day lookups that follow are cache hits. The import button
  says "Pricing day n of m". It also sends the price server no transaction
  dates. `BtcPriceService` takes an injectable `http.Client`.
- "Try Again" on the timeout dialog only closed it; the import had already
  been cancelled. It runs the import again, and "Close" closes.
- The column mapper replaced itself with the preview, so backing out lost
  every column choice. It pushes the preview, and removes itself once the
  import is done so the summary's Done still returns to the import screen.
- "Other…" currency could not be chosen: it copied the listed code into the
  field's state, so the dropdown snapped back and the field never appeared.
  The custom code must be three letters.
- Amounts with an ISO code (`GBP 12.50`, `12,50 EUR`), grouped with a narrow
  no-break space (U+202F) or a Swiss apostrophe did not parse.
- A model's per-row currency was taken as given. It is kept only when the file
  names that currency (by code, or by an unambiguous symbol); a photo, which
  gives nothing to check against, uses the account's.

### AI answers, and the models offered
- Answers were shown as raw Markdown, asterisks and all. `MarkdownText`
  renders what models use in a chat answer (headings, lists, fenced code,
  rules, bold, italic, inline code, links as text) in the chat and the insight
  card; anything else, and a half-streamed marker, stays as typed. Written in
  the app because `flutter_markdown` is discontinued.
- Gemini's answer was read from `parts.first`, dropping the rest of a frame.
  Every text part is read, skipping the model's own reasoning parts.
- A refusal or safety stop ended the stream like any other, so the partial
  answer was kept as complete. `CloudBackend.indicatesRefusal` recognises
  Anthropic's `refusal`, OpenAI/xAI's `refusal` delta and `content_filter`,
  and Gemini's safety finish reasons and `promptFeedback.blockReason`; the
  stream fails with the reason.
- xAI answers a bad key with a 400 whose `error` is a plain string echoing the
  key; it came out as "request failed (HTTP 400)". It is reported as a
  rejected key, and string `error` fields are read elsewhere.
- Model lists offered embeddings, speech, transcription, image and moderation
  models (and Ollama's embedding models). `CloudBackend.isChatModel` filters
  them; Gemini's are filtered by `supportedGenerationMethods`.
- A saved model missing from the fetched list made the chat's picker show the
  first model as if it were answering, and Settings show none. `modelChoices`
  keeps the model in use in the list.

### AI: where it goes, and what is kept
- Every chat question and answer was written to `ai_conversations` and never
  read — no screen shows them — so they piled up in the database and in every
  export of it. Nothing writes there now, and launch clears what earlier
  builds stored (`OllamaService.clearStoredTranscripts`). The table stays, so
  no schema change.
- API keys were stored under `first_unlock`, justified by a background insight
  refresh that does not exist, and that class lets a key travel in an
  encrypted backup to another device. iOS uses `first_unlock_this_device`;
  existing keys are rewritten once (`keychain_keys_device_only`), which the
  plugin does by replacing the old item. macOS keeps `first_unlock`: its
  plugin puts the class in the read query, so a change could hide every key,
  and the file-based keychain does not restore onto other devices anyway.
- A server on the local network was described as "nothing leaves", though the
  figures cross the network to another machine; a remote server over plain
  `http://` got no warning. `OllamaService.transportNoteFor` says which, under
  the URL field in Settings, onboarding and the chat's settings sheet. The
  local network still counts as the user's own hardware for consent — an open
  decision, now in TODO.

### The Stack screen's maths, and the live price
- The DCA simulator read its amount only when something else rebuilt the
  screen, so typing changed nothing until a period was tapped. It listens to
  the field now.
- Its scenarios were all valued at today's price, so the one assuming the most
  growth — which buys the fewest sats — showed the smallest figure, and
  "Optimistic" read as the worst. Each is valued at its own end price
  (`DcaSimulator.endValue`).
- The stack goal's monthly average skipped idle months, so stacking in two
  months of a year read as stacking every month and the projected date came
  far too soon. Idle months count as zero, over the last 12 complete months
  (or since the first activity).
- The live price was fetched at launch and never again. It refreshes every 10
  minutes while the app runs and on returning to the foreground
  (`BtcPriceService.startAutoRefresh`, `refreshIfOlderThan`).

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
