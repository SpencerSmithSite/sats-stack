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

---

## Not fixed — highest value first

### P0

1. **AI · the privacy disclosure is contradicted by the code.**
   `ai_privacy_disclosure.dart:79` says "Nothing is sent until you ask a
   question", but `dashboard_screen.dart:36-44` auto-generates the monthly
   insight in `initState`, POSTing the full financial snapshot (stack total,
   income, spending, surplus, category breakdown) to whatever backend is
   active — including a hosted one — with no user action, and swallowing
   failures. Gate auto-generation on `backend.isPrivate`, or require an
   explicit per-provider opt-in, and fix the sentence.
   *CLAUDE.md calls this the one claim in the app that must never be wrong.*

2. **AI · raw statements go off-device with no disclosure.**
   `import_service.dart:550-552` sends up to 100,000 characters of the raw
   statement to the active backend; there is no privacy text anywhere in
   `lib/screens/import/`. The raw file is more sensitive than the chat context
   (account numbers, every line item, balances). Show `AiPrivacyDisclosure`
   with a one-time confirm before the first off-device import.

3. **Import · `CsvImportService` silently caps every import at 100 rows.**
   `csv_import_service.dart:47,197`. Rows 101+ are never parsed, never counted
   as duplicates, never reported. A 2,400-row statement imports 100 rows and
   the sheet says "100 rows". Note there are **two divergent import pipelines**
   (`CsvImportService` + `CsvImportSheet`, and `ImportService` + `screens/import/`),
   both reachable from `main.dart`; the legacy one also lacks 2-digit-year
   support (`:141,150` require `(\d{4})`, so a Chase `01/02/25` export drops
   100% of rows), parenthetical negatives and trailing minus. **The cheapest
   real fix is to delete it and route `CsvImportSheet` through `ImportService`**,
   which now has all of it.

### P1

4. **Data · `fiatCurrency` is hardcoded `'USD'` on every manual and legacy-CSV
   entry** — `add_transaction_sheet.dart:213`, `csv_import_service.dart:324` —
   while `transaction_list_item.dart:113` renders using the stored value. A GBP
   user's £40 expense displays as "-$40.00", and sats were computed from the GBP
   price, so the two now disagree. Pass `app.currencyNotifier.value`.
   Related: `add_transaction_sheet.dart:119` hardcodes `$` in the sats→fiat hint.

5. **Data · month ranges end at `23:59:59`**, used with `!isAfter(lastDay)` at
   `dashboard_service.dart:37,92,108,181,252` and `budget_service.dart:80`.
   Anything in the last 999 ms of a month belongs to no month — reachable,
   because `add_transaction_sheet.dart:47` seeds the date with
   `DateTime.now()`. Use an exclusive `isBefore(firstOfNextMonth)` bound.

6. **Data · renaming a category orphans every transaction in it.**
   `category_service.dart:37-50` updates `Categories.name`, but
   `Transactions.category` is free text matched by string
   (`budget_service.dart:86`). The budget card drops to "$0 of $500", no
   overspend alert fires, and the pie chart shows a phantom slice. Update both
   tables in one transaction.

7. **Data · BTC-denominated imports write BTC units into `amountFiat`**
   (`import_service.dart:964-990`), and `DashboardService` sums that column as
   money: a 0.05 BTC deposit reads as "$0.05". Convert at import time using the
   historical price. Same root cause as the discarded source currency — the
   user's per-source choice (`import_source_setup_screen.dart:30`) is never
   read; every rules/mapping path hardcodes `'USD'` (`:700,879,1233`).

8. **UI · missing `mounted` guards after `await`** — seven in
   `csv_import_sheet.dart` (44,49,53,59,70,78,84: not one in the file), plus
   `settings_screen.dart:323,371,484,600`, `add_transaction_sheet.dart:233`,
   `set_budget_sheet.dart:81`, `stack_screen.dart:92`. Each is a real
   `setState() called after dispose()` — e.g. dismiss the CSV sheet while the
   native picker is open. Mechanical fix; `_testCloudConnection` already does it
   right.

9. **UI · streams and futures constructed inside `build()`** —
   `transactions_screen.dart:225`, `stack_screen.dart:118`,
   `dashboard_screen.dart:121,301`, `analytics_screen.dart:109`,
   `budgets_screen.dart:100`. Every `watch*()` builds a new Drift stream, so
   each rebuild re-subscribes and resets to `waiting`: **every keystroke in the
   transactions search box replaces the list with a spinner and re-queries the
   table**, and the dashboard's Wallets section vanishes and returns on each BTC
   price tick. Hoist into `initState`/memoise on the month.
   Worse: `transactions_screen.dart:537` runs `categoryService.getAll()` *per
   row* in a `FutureBuilder`; `dashboard_screen.dart:370` does the same on every
   price tick.

10. **Data · bulk inserts are not wrapped in a transaction**
    (`import_service.dart:925-1005`, `csv_import_service.dart:300-331`; xpub is
    now fixed). Each commit fires `watchAll()` → `main.dart:138` →
    `checkAndNotify()` → three full table selects, plus every mounted
    `StreamBuilder`. A 300-row import means ~900 full-table selects and a
    multi-second freeze; a kill mid-loop leaves the two tables inconsistent.
    `generateDueRecurring` already shows the right pattern.

11. **AI · `aiEnabledNotifier` drifts between the two choosers.**
    `settings_screen.dart:269` omits the "hosted provider with a key" term that
    `onboarding_screen.dart:146` has, so a mobile user with a saved Anthropic
    key loses the AI tab by switching provider and back. Separately
    `main.dart:80-82` seeds it from a probe that is `unawaited`, so on-device
    providers lose the tab after every restart. Extract one
    `aiShouldBeEnabled(AiProvider)` helper — CLAUDE.md claims these two paths
    cannot drift, and they have.

12. **AI · LM Studio claims `isPrivate: true` unconditionally**
    (`ollama_service.dart:98-109`) — "Nothing leaves your device" — while its
    base URL is a free-text field the user can point at a VPS. Ollama's own
    wording is honest; copy it, or derive the claim from the host.

13. **AI · mid-stream provider errors are silently swallowed**
    (`cloud_backend.dart:456-481`). An error frame arriving after 200 tokens
    ends the stream, and the truncated answer is persisted as complete. Also
    `max_tokens: 4096` is hardcoded with no truncation notice.

14. **AI · a partially-masked API key can reach the screen.**
    `describeError` prefers the provider's message even for 401, and OpenAI's
    401 body contains `Incorrect API key provided: sk-proj-ab****XYZ`, printed
    verbatim by `ai_chat_screen.dart:165`. Use the canned string for 401/403.

15. **Import · editing an imported BTC row zeroes it.**
    `transaction_edit_sheet.dart:68` formats with `toStringAsFixed(2)`, so
    0.00047 BTC opens as "0.00"; saving writes 0.0 and passes the `< 0` guard.

16. **Data · `BudgetService.upsert` is read-then-write with no transaction and
    no unique index on `budgets.categoryId`** — double-tapping Save creates two
    rows, after which every later `upsert` for that category throws
    `StateError` from `getSingleOrNull` and the budget can never be edited
    again. Wrap in a transaction and add the index.

17. **UI · the Stack hero card and chart gridlines are hardcoded dark** —
    `stack_screen.dart:329` (`0xFF1A1200`/`0xFF2A1F00` with white text) and
    `:535` (5%-opacity white gridlines, invisible in light mode). Survivors of
    the light-mode pass recorded as complete in CLAUDE.md.

18. **UI · `/ai` has no redirect when the tab disappears.** `app.dart:130-139`
    drops the path from `_tabPaths` and `_indexForLocation` falls back to 0, so
    the AI screen stays rendered with Dashboard highlighted and no matching tab.

19. **UI · a notification is fired from inside `build()`** —
    `budgets_screen.dart:124`, guarded by a module-level `Set` that is never
    cleared, so re-exceeding a budget in the same month never alerts again.

### P2 — worth doing, not urgent

- **No indexes exist anywhere in the schema.** Hot unindexed columns:
  `transactions.date` (sorted and range-filtered everywhere), `.walletId`,
  `.category`, `.recurringPeriod`, `budgets.categoryId`,
  `importedTransactions.sourceId`, `descriptionCategoryMappings.(sourceId,
  description)`. Needs `@TableIndex` + a v6 migration step.
- **Foreign keys are never enforced** — no `beforeOpen`, so every
  `.references(...)` is decorative and `PRAGMA foreign_keys` stays off.
- `watchDashboard` ignores `AppSettings`, so the stack goal does not propagate
  (masked today by finding 9 — fixing that exposes this). `watchPerWallet`
  misses wallet changes and re-scans all transactions once per wallet.
  `BudgetService.watchProgress` double-fires and never closes its controller.
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
- `notification_service.dart:24-35` passes no `iOS:` initialisation settings and
  only resolves the macOS permission plugin, so **notifications never appear on
  the TestFlight iOS build**. ID scheme collides with the stack-goal ID at
  `categoryId == 4999`.
- xpub derivation runs on the UI isolate; there is no scan cursor, so every
  rescan re-fetches from index 0 on both chains.
- Onboarding's Bitcoin-server page is a non-scrolling `Column` with a text
  field — RenderFlex overflow on a small phone when the keyboard opens.
  `_onboardingRedirect` issues a DB select on every navigation.
  Settings rebuilds its whole 1,724-line tree on every keystroke in the API-key
  and server fields.

### Duplication / shape
- Sats formatting is reimplemented **11 times** with the same regex and subtly
  different sign handling, while `SatConverter.formatSats` exists and is used in
  6 places. The category colour map exists **3 times with divergent colours**
  (Shopping is purple, blue or grey depending on the screen) and none of them
  consults the user's own per-category colour from the DB. `_SectionHeader` ×4,
  month selector ×3 with the arithmetic triplicated.
- `sat_amount_display.dart` (95 lines) is dead code; so are `ElectrumService`,
  `BitcoinNodeService`, `BitcoinDataSource` and `ManageWalletsSheet` — they
  compile but nothing references them.
- `settings_screen.dart` (1,724), `onboarding_screen.dart` (1,745) and
  `stack_screen.dart` (1,156) each want splitting; `on_device_ai_section.dart`
  is the precedent.
- `test/transactions_zz_scratch_test.dart` is a GoRouter scratch file with
  `debugPrint`s and 101 identical test names — delete it.

### Test gaps
No test covers: a v1→v5 migration against a fresh `onCreate`, month-boundary
aggregation, `BudgetService.getProgress` after a category rename, the dedup-hash
contract across the three salts, or any stream reactivity.

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
