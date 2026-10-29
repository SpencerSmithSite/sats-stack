# TODO

**The single list of what is left to do.** If it is not here, it is either done
or nobody has decided to do it.

History lives elsewhere and is not duplicated into this file:

- [`AUDIT.md`](AUDIT.md) — the 2026-10-17 codebase audit: every finding, what
  was wrong, and what was fixed. Read it before re-investigating anything in
  the data, import, AI or Bitcoin layers.
- [`AGENT_ACCESS_PLAN.md`](AGENT_ACCESS_PLAN.md) — design doc for agent access
  over MCP.
- `git log` — each commit says what was wrong rather than what changed, so the
  history reads on its own.

## How this stays tidy

- **One branch per change**, named `fix/…`, `feat/…`, `refactor/…` or `ci/…`,
  cut from `main`. Delete it as soon as its PR merges; `main` should normally
  be the only branch on the remote.
- **Everything lands through a PR.** CI (`.github/workflows/ci.yml`) runs
  `flutter analyze` and `flutter test` on every one.
- **Zero analyzer issues** is the standing bar, infos included. CI runs a bare
  `flutter analyze`, which exits non-zero on anything, so a new deprecation
  cannot drift in unnoticed.
- **When an item lands, move it to `AUDIT.md`'s "Fixed" section**, so this file
  only ever shows open work.

---

## Next

> **Second review pass, 2026-10-18.** Four independent reviews of the *current*
> code — data layer, AI/import, UI, and everything outside `lib/` — rather than
> a re-read of `AUDIT.md`. They found ~70 items, including two that would have
> shipped broken and three regressions introduced by the audit's own fixes.
> Those are fixed (see `AUDIT.md`). Everything below is what they found and is
> still open, in the order I would do it.

### 10. Decisions and upgrades the CI pass surfaced

- **Encrypt the database.** Decided 2026-10-20: yes. The design is in
  [`DATABASE_ENCRYPTION_PLAN.md`](DATABASE_ENCRYPTION_PLAN.md) — SQLCipher,
  a random key in the keychain, an in-place migration that copies drift's
  `user_version` by hand — with two decisions still open (the export format,
  and whether macOS waits for Developer ID signing).
- **Android toolchain, next floor.** Flutter 3.47.2 warns that Gradle 9.1,
  AGP 9.0.1 and Kotlin 2.3.20 will be required soon. AGP 9 is a major
  release (built-in Kotlin, changed DSL defaults), so do it on its own and
  check every plugin builds.
- **Typed JSON parsing** in place of the 43 `dynamic` calls
  `avoid_dynamic_calls` would flag, then enable the rule.

> Items 11–14 were already tracked before the second pass. They are still
> open and still worth doing; they are simply less urgent than 1–10.

### 11. Wire up the Bitcoin data-source picker

`ElectrumService`, `BitcoinNodeService` and `BitcoinDataSource` compile and
are referenced by nothing; they exist for this feature.
(`scripthash_test.dart` does not test `ElectrumService`: it tests a helper
defined inside itself.)

- Settings → Servers gains a picker: Mempool/Esplora (today's only path), the
  user's own Electrum server, or Bitcoin Core RPC.
- `XpubService` reads history through the chosen source instead of hardcoding
  Esplora HTTP.
- Electrum needs its "trust this certificate?" flow to be reachable. The client
  verifies certificates properly now and `fetchCertificateFingerprint` exists
  for exactly this prompt, but no screen calls it, so a self-signed server
  cannot currently be accepted at all.
- Bitcoin Core is for connection testing and future broadcasting only — it is
  not usable for address-history scanning, which is why Electrum is here too.

### 12. xpub scanning: batch the requests further

Derivation now runs in an isolate and a window's requests overlap, so a scan is
no longer a strictly serial walk. What is left is the request count itself: a
resync still asks about every derived address.

**The "scan cursor" this file used to propose is not safe, and should not be
built as described.** Skipping addresses below a high-water mark would miss new
payments to an address that was already used, and skipping the gap window would
miss an address funded since the last scan — so nothing in the range is
actually safe to skip. Reducing the request count needs a server that can
answer about many addresses at once, which is the Electrum work in item 11
(`blockchain.scripthash.subscribe`), not a cursor.

### 13. Close the named test gaps

- **A v1 → v8 migration against a fresh `onCreate`.** There is no generated
  schema history to migrate against, which is why `migrateToV6` and
  `migrateToV7` are named methods the tests call directly. Real coverage means
  generating drift's schema history, then asserting an upgraded database
  matches a freshly created one.
- **Widget-level stream reactivity.** The import path's single-commit guarantee
  is asserted at the service level, but nothing checks that a screen subscribes
  once and survives a rebuild — which is the bug class the split just fixed.
  `dashboard_rebuild_test.dart` now shows how to pump a whole screen against
  real services on an in-memory database (including the teardown drift needs),
  so the other four tabs can follow the same pattern.

### 14. Decompose Settings properly

`settings_screen.dart` is still 1,575 lines and was deliberately left out of
the file split. Its bulk is one state class holding every controller and every
connection test, so per-section files mean handing all of it back in as
parameters and callbacks. That is a design change with real behavioural risk,
worth doing on purpose rather than as a move.

### 15. Third review pass, 2026-10-21 — still open

Fixed items from this pass are in `AUDIT.md` ("Third pass"), in PRs #22–#28.
Everything below was checked against the code and is still open. Roughly in
the order to do it; the first group can lose or misstate the user's data.

**Data and money**
- **Product decision:** should fiat income/spending include Bitcoin
  movements? Today an xpub self-transfer counts as both.

**Import flow**
- A cancelled import can resume and upload, and a new import clears the old
  one's cancel flag (state on the singleton; needs a per-import token).
  Leaving the import screen does not cancel.
- The column mapper reads headers from row 0 rather than the detected header
  row, and its dates overflow (25/12/2025 as MM/DD becomes 2027) instead of
  being rejected; DD/MM only accepts `/`.
- On-device AI is never ready for import (no selected model); a PDF gets no
  heuristic fallback when the AI fails; AI input is cut at 100k characters
  without saying so; the saved column mapping is written before parsing and
  cannot be cleared; learned category mappings key on the edited
  description; renaming a system category breaks keyword categorisation.
- Historical prices are fetched one per second, serially, with no progress.
- Smaller: mapper back navigation, "Other…" currency, a no-op "Try again",
  ISO codes and U+202F in amounts, trusting the model's per-row currency.

**AI**
- Markdown is shown raw in the chat.
- Live model lists are unfiltered (embeddings, TTS…), and the dropdown can
  show a model other than the one in use.
- Gemini reads only `parts.first`; refusals and safety stops are saved as
  complete answers; xAI's 400 for a bad key gets a generic message.
- Chat transcripts are written to `ai_conversations` and never read — every
  prompt and answer accumulates in the exported database for no feature.
  Stop writing them or build the history screen.
- `KeychainAccessibility.first_unlock` is justified by background work that
  does not exist; `first_unlock_this_device` is the safer class (see also the
  encryption plan's 2026-10-21 notes).
- LAN hosts count as "nothing leaves"; plain `http` to a remote host gets no
  warning.

**UI**
- `assets/fonts/RobotoMono-*.ttf` are GitHub HTML pages, not fonts (since
  the initial commit): every monospaced figure falls back to the system font,
  and ~600 KB of HTML ships in the bundle. Needs the real files (Apache 2.0);
  then declare the Medium face with `weight: 500`.
- Remaining overflows at large text: the transaction row's category line, the
  hero's fiat row, the budget card's amounts, `StackGoalTile`, Settings' button
  rows.
- Remaining contrast: the budget card's raw orange sats figure and green
  "left" text (after #26), selected chips' labels in the raw category colour.
- Analytics ignores user category colours; `CategoryPalette` seeds disagree
  with the database seed (four system categories are the same grey).
- The DCA simulator ignores typing (no listener) and its scenarios rank
  backwards (valued at today's price); the stack goal's monthly average skips
  idle months, so the projected date is optimistic; the live price is never
  refreshed while the app is open.
- The hero's "Import a Bitcoin wallet" pill looks tappable and is not; a
  dead gap between "Add notes" and "Repeat"; copy still says "xpub address"
  and "bank CSV" (PDF and photo exist); the 33 px icon-grid targets; icon
  buttons without tooltips; error snackbars behind sheets; a stream built in
  `CategoriesSheet.build`; a month change briefly shows the previous month.
- The splash adds ~2.5 s to every cold start, ignores reduced motion, and its
  `initFuture` is never passed.

**Native, build, CI**
- CI builds debug only, where the debug manifest declares INTERNET whatever
  `src/main` says — so it cannot catch what its comment says it catches. Add a
  release-variant manifest check (and R8).
- `ndkVersion` is pinned to r27 (a leftover; Flutter's default is 28.2), and
  CI downloads it every run.
- No Android 12+ splash config (white flash); notifications use the
  full-colour launcher icon; no `NSLocalNetworkUsageDescription` for a LAN
  Ollama; Gemini Nano download progress is always indeterminate though the API
  gives a total; a transient AICore error hides Nano for the session.
- The iOS icon set mixes legacy and universal entries (one with a bogus
  `luminosity: light`); the launch image is iPhone-only and its 1x is the
  wrong size, and `flutter_native_splash` would overwrite it.
- `assets/icons/` is bundled but never loaded; `file_picker` 10 pulls in
  DKCamera, CoreLocation and MediaPlayer.
- Dead native config: the macOS Podfile's sqlite3 block, the iOS
  `use_modular_headers!` rationale, a mangled
  `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`,
  `enableJetifier`, legacy mipmaps, Windows/Linux template identity.
- CI hygiene: unpinned Xcode, Node 20 actions, no Gradle/Pods cache, no
  top-level `permissions:`, no check that generated drift code is current.

**Tests that cannot fail, and dead code**
- `month_boundary_test`'s aggregate group (see AUDIT, seconds); the DST test
  passes trivially in CI's UTC (set `TZ`); the unknown-xpub-prefix test fails
  on its checksum, not the version; `scripthash_test` tests itself;
  `database_restore_test`'s failed-copy case never tears the target;
  `ai_enabled_test`'s seed case is always true on desktop; the privacy
  invariant cannot catch a forgotten hosted provider (assert the private set
  exactly); `tab_state_test` does not use the app's router.
- `auto_category_test` makes real network calls — add a
  `flutter_test_config.dart` that refuses non-loopback HTTP.
- Untested: the xpub money maths beyond one receive, the keychain migration,
  export/import, budget thresholds, the DCA simulator.
- Dead: `TransactionService.getAll`, `WalletService.getAll/watchAll`,
  `BudgetService.watchAll`, `BtcPriceService.getCachedPrice`,
  `ImportService.listSources/getTransactionsForSource`, the
  `*Connected` getters, `GeminiNanoState.needsDownload`,
  `CloudProvider.fromId`, `AppConstants.appName/coinGeckoPriceUrl/defaultCurrency`,
  `ImportTier.pdfExtracted`, `ImportFileType.unknown`, an empty
  `widget_test.dart`. `clearAllApiKeys` does not delete the RPC password
  entry item 11 will use.

---

## Smaller items

- **Tab roadmap**, from the deleted `SatsStackNotes.md`: Accounts and Goals
  as tabs of their own, and a Cash flow view.
- **Transaction search/filter polish** — fuzzy matching, date-range picker.
- **Home screen widget** — stack balance + BTC price. Needs `home_widget` and
  an app group entitlement.
- **iCloud / local automatic backup** — complements the manual export in
  Settings → Data, which now takes a consistent `VACUUM INTO` snapshot and
  keeps a `.bak` on restore.
- **BTC price alerts** — threshold notification via
  `flutter_local_notifications`, which now actually fires on iOS.
- **Register the macOS bundle id** (`app.satsstack.SatsStack`, settled on
  2026-10-20) with Apple, and switch `SecureKeyStore` to the data-protection
  keychain. Needed for any macOS distribution anyway; the
  comment in `secure_key_store.dart` explains why the file-based one is in use
  (the ad-hoc-signed target cannot carry the entitlement, so every write fails
  with `errSecMissingEntitlement`).
- **Verify a real request against each hosted provider.** Every wire format is
  unit tested against the documented shape, but nothing has run against a live
  endpoint with a real key — that needs four paid accounts.

---

## Known broken / unfinished

See item 15 for what the 2026-10-21 pass found still open, starting with the
data-loss items. The open decisions are in item 10.

## Done, for reference

Both of the original items in this file are finished, and the reasoning behind
them is in `git log` rather than here:

- **Cloud LLM providers** — `CloudProvider` + `CloudBackend`, four `AiProvider`
  values, keys in the keychain, a grouped chooser shared by Settings and
  onboarding. Model lists are fetched live rather than hardcoded, because a
  hardcoded list starts going stale the day it ships.
- **Onboarding reflects the full backend list**, with a per-backend privacy
  line — a blanket "everything stays on your device" is false the moment a
  hosted provider is selected.
