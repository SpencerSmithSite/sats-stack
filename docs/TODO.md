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

### 1. Ships broken or cannot ship

- **GPLv3 + proprietary Syncfusion + the App Store.** `LICENSE` is GPL-3.0 and
  `README.md:137` says so, while `pubspec.yaml:74` bundles
  `syncfusion_flutter_pdf`, which is not open source — its terms cannot satisfy
  GPLv3's requirement that the combined work be redistributable under GPLv3.
  Independently, GPLv3's anti-DRM and installation-information terms are the
  known conflict with App Store distribution (the VLC precedent). **This is a
  decision, not a fix:** relicense to MPL-2.0/Apache-2.0, or drop Syncfusion
  for a GPL-compatible text extractor. Cheap to resolve now because the author
  holds the copyright. Not legal advice.
- **macOS: the hand-copied LiteRT-LM frameworks are ad-hoc signed** (`macos/
  Podfile:162,171` run `codesign --sign -`) and `Release.entitlements` has no
  `com.apple.security.cs.disable-library-validation`. This works *only* because
  the whole app is ad-hoc signed; the moment the target is signed with a
  Developer ID — which registering the bundle id requires anyway — library
  validation refuses to `dlopen` them and notarization rejects ad-hoc nested
  code. Every `install_name_tool`/`codesign` in that phase ends in `|| true`,
  so the failure is swallowed at build time. Drop the `|| true`s.
- **That build phase is arm64-only and reads `${HOME}/Library/Caches`**
  (`macos/Podfile:120-137`). On an Intel Mac it warns and the build *succeeds*
  with a broken app. Select from `$ARCHS` and `exit 1` rather than warn.
- **`flutter_gemma` and `flutter_gemma_litertlm` are both discontinued** on
  pub.dev (1.4.2 / 1.3.1 installed; 1.11.4 / 1.8.6 are the last versions that
  will ever exist). The pubspec comment chose this package *on maintenance
  grounds*; that reasoning has inverted. Options, with what breaks:
  (a) stay — nothing breaks today, no fix ever arrives, including for the
  `-headerpad_max_install_names` workaround above; (b) move to the final
  versions — resolvable, but `createModel`, the `FlutterGemma.*` statics and
  `ModelFileType` all moved between 1.4 and 1.11, and the macOS build phase is
  written against 1.3.1's layout; (c) replace with a direct LiteRT-LM FFI
  binding — the only route that keeps the `.litertlm` catalogue and already
  downloaded models; (d) drop the backend — it is the only one of six with a
  hand-written Xcode phase, a multi-gigabyte download and an unmaintained
  native dependency, and two other on-device backends exist.
- **macOS bundle id, product name and copyright are template placeholders.**
  `AppInfo.xcconfig:11` is `com.satsstack.satsStack` against iOS's
  `app.satsstack.SatsStack`; `:14` reads "Copyright © 2026 com.satsstack",
  shown verbatim in the About box; `:8` makes the window title `sats_stack`.

### 2. The native bridges do not stop generating when cancelled

`android/.../GeminiNanoBridge.kt:132-163` and
`ios/Runner/FoundationModelsBridge.swift:184-226`. Real on both platforms, for
different reasons: Kotlin's `onCancel` cancels a job the collector never
suspends on (and `scope` is a local in `onListen`, so it cannot be cancelled at
all), while Swift's `catch` does not distinguish `CancellationError`, so
cancelling emits `generation_failed` into a torn-down sink. Both hold a single
`task`/`job` field on a single handler instance, so a second request orphans
the first.

**This narrows an `AUDIT.md` claim.** `serialisedOnChannel` releases its queue
slot the instant the Dart subscription is cancelled, not when the native side
stops — and `stream_resilience_test.dart` runs under `flutter test`, which has
no engine, so it exercises the Dart queue alone. Net effect: cancelling one
answer can corrupt or fail the next one, and on Android the model stays busy
after the queue has moved on. Fix needs native work on both sides.

### 3. Currency is still mixed in every aggregate

- **`amountFiat` is summed across currencies.** `transactions.fiatCurrency` is
  written by four paths and read in exactly one place — the row label at
  `transaction_list_item.dart:113`. No aggregate filters or converts by it, and
  the import flow deliberately supports a per-source currency. A GBP user with
  a USD card gets dashboard spending, budget progress, the pie chart, YTD and
  the exported CSV adding USD to GBP under a `£` label — while the transactions
  list shows each row correctly, so the two screens visibly disagree. Convert
  at read time via `BtcPriceHistory`, or filter aggregates to the active
  currency and surface what was excluded.
- **The live edit path writes a recomputed amount under the row's old
  currency.** `transaction_edit_sheet.dart:198` derives the figure from
  `priceNotifier.value` — the price in the *active* currency — then stores
  `fiatCurrency: Value(tx.fiatCurrency)`. Editing a USD row while the app is in
  GBP writes a GBP number labelled `$`. `AUDIT.md` records this as fixed, and
  it is — in `AddTransactionSheet`'s editing branch, which is **dead code**: its
  only call site is the add path. Fix the real path and delete the dead branch.

### 4. Light mode fails contrast, in the places that matter most

Measured, not guessed. None of these is a *hardcoded dark colour* — the audit's
light-mode pass looked for those and found them all. These are colours tuned
for dark and reused on light.

- `AppColors.textSecondary` (`app_colors.dart:21`) is one grey for both themes:
  **3.41:1** on the light background, below the 4.5:1 AA floor, used at 10–11px
  across **126 sites in 31 files** — every caption, metric label, date header
  and category name.
- `AppColors.bitcoinOrange` as *text* is **2.30:1** on a light card — the sats
  figure on every transaction row and every spending bar, the "View Analytics"
  link, the app-bar price. Fine as a fill, border or icon; only small text
  breaks.
- Accent-coloured body copy over an 8%-alpha tint of the same accent, measured
  at **1.94–2.9:1**, in `settings_widgets.dart:32-107`, `RouteRow:173`,
  `on_device_ai_section.dart:33,60`, `ai_provider_page.dart:315,337`,
  `bitcoin_server_page.dart:87,106`, `add_wallet_sheet.dart:304,325,336,355`.
  The worst of it is the Settings → Servers banner explaining *which third
  parties can see your Bitcoin addresses* — the least readable text in the app
  is the copy that most needs reading. `ai_insight_card.dart:117-123` already
  does this correctly in the same codebase: accent for icon and heading,
  `onSurface` for the body.

Fix: resolve `textSecondary` from the theme (light needs ≈`#5F5E57`), add an
on-light orange (≈`#9A5600`) used only at the text sites, and one shared
`InfoBanner` that keeps the accent for icon and heading only.

### 5. Tab state is destroyed on every tab switch

`app.dart:73-97` uses `ShellRoute`, not `StatefulShellRoute`, so each tab is a
different child widget *type* and the element tree cannot reconcile — the whole
screen State is destroyed. Set a filter and a search on Transactions, tap
Dashboard, tap back: both are gone, the scroll position is lost, and the table
is re-queried from scratch behind a full-screen spinner. Same for the Stack
period and DCA input, and the selected month on Budgets and Analytics; the
dashboard insight re-runs two DB reads per visit. `StatefulShellRoute.indexedStack`
with one branch per tab fixes it and removes most of the per-visit cost the
stream hoisting was aiming at.

### 6. Accessibility

- **There is no `Semantics` or `semanticLabel` anywhere in the UI layer** —
  zero matches across `lib/features`, `lib/shared`, `lib/screens`. Anything
  built from `GestureDetector` is announced as an unlabeled button or not at
  all, including both month selectors, the insight refresh, the price chip, the
  period chips and the colour swatches. The charts expose no values.
- **Tap targets below the 44×44 floor**: month-selector arrows are 20px and
  22px (`month_selector.dart:57`, `budgets_screen.dart:353,363`), the insight
  refresh is **14px** (`ai_insight_card.dart:92`), the price chip is 21px tall
  (`btc_price_chip.dart:59`), the pill chips ~20–24px.
  `analytics_screen.dart:186` already uses `IconButton` correctly — copy it.
- **Overflow at large text scale**: in `transaction_list_item.dart:109-129`,
  `dashboard_screen.dart:614-643` and `spending_chart.dart:142-160` the
  trailing amount `Column` is not flex, so the row overflows rather than
  shrinking; `_CategoryBar` also hardcodes a 100px label. The app-bar month
  selectors overflow at 2× scale — `transactions_screen.dart:143` already uses
  `FittedBox` and the other three screens do not.

### 7. Parsing gaps the import rework did not reach

- **Dot-grouped thousands.** `_normalizeDecimalSeparator` has a 3-digit rule
  for commas and no mirror for dots, so a German `2.500` becomes **2.5** — a
  1000× understatement with nothing to tell the user — and `1.234.567` drops
  the row. A naive mirror rule would break BTC amounts (`0.123`), so this needs
  the per-file inference treatment `_inferDayFirst` got.
- **`_inferDayFirst` takes the first decisive sample, not a vote**, so one
  US-formatted row in a merged UK export decides the whole file.
- **The PDF heuristic tier got none of the date work**: `_parseDate` is called
  with the default `dayFirst: false` and `datePats` has no dotted pattern, so a
  UK PDF line `04/03/2025` is booked as 3 April and a German `01.02.2025`
  matches nothing at all. This is the tier a user lands on when they decline
  off-device consent. Its amount regex has the same dot-grouping gap.
- **The delimiter sniffer reads the first non-empty line**, which for the many
  exports that start with a title or account summary is not the header; and
  only `\r\n` is normalised, so a classic `\r`-only export is one row.

### 8. The import consent gate needs a way out

- Consent is persisted at the tap, permanently, per provider, with **no revoke
  UI anywhere** — and nothing afterwards tells the user the upload happened.
  One "Send to Anthropic" tap and every later CSV, PDF and photo import
  uploads silently, while the preview screen labels the result "Parsed via
  **Ollama AI**" regardless of provider and `AiPrivacyDisclosure` promises
  "Nothing is sent unless you ask for it". Add a revocable Settings row, label
  the tier with the real provider, and show the recipient on the preview.
- `setOffDeviceImportAllowed(true)` is written before anything is sent and is
  not rolled back if the import is then cancelled.
- The consent dialog's copy is file-specific ("the file is read on this device
  with the built-in rules instead") but is shared with the image flow, which
  has no local fallback at all.
- The 5-minute timeout keeps running while the dialog is open, so it can fire
  behind it and stack a second dialog.
- `isLocalEndpoint` returns **true** for a URL Dart cannot extract a host from
  — `ollama.example.com:11434` parses as a *scheme* — so a plausible bare
  `host:port` entry is treated as local: no consent prompt, auto-insight on,
  and a false privacy claim, while the request fails anyway. Normalise on save
  (`XpubService.normalizeBaseUrl` already does exactly this, tested) and fail
  **closed** for an unparseable URL.
- `_handleImage` swallows the `InferenceException` that says *why* ("Apple
  Intelligence cannot read images"), showing generic advice about llava
  instead; and it asks for consent before checking the backend can serve the
  request at all.

### 9. Smaller correctness items

- A category *rename* can silently move another category's transactions:
  `Categories.name` has no unique constraint and the update matches on name, so
  two categories can share a name and a later rename rewrites both. Budget
  progress and the CSV export are keyed by name too, so one of the pair reads
  zero spend forever and neither can be deleted. Needs a unique index (v8) and
  a check in the sheet.
- A failed database restore leaves `app.db` **closed** for the rest of the
  session — every later query throws. Restore from the `.bak` and tell the user
  to relaunch.
- Today's intraday BTC price is cached permanently (`DoNothing()` on a
  same-day row), so every transaction imported today keeps a mid-day quote.
- `ImportSummary.imported` counts `importedTransactions` writes, not main-table
  writes, so re-importing a file into a new source reports N imported while the
  Transactions screen gains nothing.
- The xpub scan dedupes against **every** wallet, so adding the same xpub twice
  syncs the second to zero rows while reporting them all as skipped.
- The Stack screen recomputes four O(n) aggregates on every BTC price tick;
  the Dashboard's price and currency `ValueListenableBuilder`s wrap the whole
  content subtree, so a price poll rebuilds all ten transaction rows.
- Four moved widgets read `app.currencyNotifier.value` in `build` without
  subscribing — they work only because `stack_screen.dart:151` wraps them in a
  `ValueListenableBuilder` that *discards* the value purely to force a rebuild.
- `TransactionListItem` carries its own currency-symbol table, duplicating
  `CurrencyUtils.symbolFor`.
- Three more unguarded `setState`-after-`await` (`add_transaction_sheet.dart:130`,
  `transaction_edit_sheet.dart:136`, `import_file_screen.dart:563`).
- `SetGoalSheetState` is public and should not be; four constructors the split
  touched have `super.key,required this.x` crammed onto one line.
- `_generateInsight` swallows every failure, including the specific messages
  `CloudBackend.describeError` already produced.
- Stale copy: image import still says "Connect Ollama, LM Studio, or Maple".

### 10. CI, lints and docs

- **CI compiles nothing native.** `flutter analyze` + `flutter test` on ubuntu
  cannot reach a single platform finding above: no Podfile is evaluated, no
  entitlement read, the Android manifest merge never runs, neither bridge is
  compiled. In value order: `dart format --set-exit-if-changed`,
  `flutter build apk --debug` (would have caught the INTERNET permission),
  and a `macos-latest` job running `flutter build ios --no-codesign` and
  `flutter build macos`. Also use `--enforce-lockfile`.
- `claude.yml` runs on an `@claude` mention from **any** account on a public
  repo, with no `author_association` guard — unbounded token and compute use.
  Neither Claude workflow has `concurrency`, so three pushes start three
  reviews. (Both correctly use `pull_request`, not `pull_request_target`, so a
  fork PR cannot reach the secret.)
- `analysis_options.yaml` enables **no rules** — the `linter.rules` block is
  entirely commented out — so "zero analyzer issues" is only as strong as
  `flutter_lints` defaults. Nothing enables `prefer_single_quotes`,
  `require_trailing_commas`, `unawaited_futures` or `avoid_print`.
  `flutter_lints` is `^5.0.0`; 6.0.0 is current. The `analyzer.exclude` list
  names five directories that contain no Dart and is inert.
- Two of the four "Critical package version pins" in `CLAUDE.md` no longer have
  a live reason: `fl_chart` 1.2.0 and `drift_flutter` 0.3.1 both appear in
  `pub outdated`'s *Resolvable* column, so the stated conflicts are gone (each
  is still a real API change, so this is about correcting the table, not
  upgrading blind). `url_launcher ^6.3.0` is not a pin at all. The
  `flutter_secure_storage` pin does still hold, but is holding a discontinued
  transitive package.
- `CLAUDE.md` is stale in more places than item 5 of this file admitted: Dart
  3.11.3 → **3.13.2**, the iOS Podfile platform is **16.0** not 12.0, the
  schema notes describe three migrations where there are seven, and the
  `NSPhotoLibraryUsageDescription` rationale is now wrong (the app uses the
  photo library directly). `README.md:26,50,63,65,110` repeats some of it and
  still describes AI as Ollama-on-desktop.
- `SatsStackNotes.md` is tracked at the repo root and contradicts this file —
  it asks for zpub import and category editing, both shipped. Fold its one live
  item (user-editable inflation rate) in and delete it.
- `test/dedup_hash_test.dart` pins the salt table against itself rather than
  against the call sites: every salt is hand-typed and no call site is invoked,
  so a regression where a caller changes its salt passes untouched. It also
  misses the collision that actually bit (two series with the *same* anchor).
- `ITSAppUsesNonExemptEncryption` is absent from `ios/Runner/Info.plist`, so
  every Transporter upload stops for the export-compliance question.
- Android declares `CAMERA` with no runtime permission handling anywhere (no
  `permission_handler` in pubspec, no request in `lib/`). Declaring it is what
  *creates* the requirement for `ACTION_IMAGE_CAPTURE`, so the camera import
  can throw `SecurityException` on device; undeclared, the capture intent needs
  no grant. Needs device verification either way.


> Items 11–14 were already tracked before the second pass. They are still
> open and still worth doing; they are simply less urgent than 1–10.

### 11. Wire up the Bitcoin data-source picker

`ElectrumService`, `BitcoinNodeService`, `BitcoinDataSource` and
`ManageWalletsSheet` all compile, are unit-tested where they can be
(`scripthash_test.dart`), and are referenced by nothing. They are the only dead
code in the repo, and they exist for this feature:

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
answer about many addresses at once, which is the Electrum work in item 1
(`blockchain.scripthash.subscribe`), not a cursor.

### 13. Close the named test gaps

- **A v1 → v7 migration against a fresh `onCreate`.** There is no generated
  schema history to migrate against, which is why `migrateToV6` and
  `migrateToV7` are named methods the tests call directly. Real coverage means
  generating drift's schema history, then asserting an upgraded database
  matches a freshly created one.
- **The dedup-hash contract across its three salts** — `''` for CSV re-import,
  a timestamp for manual entries, `xpub_<txid>` for chain rows. Each salt means
  something specific and nothing pins the distinction.
- **Widget-level stream reactivity.** The import path's single-commit guarantee
  is asserted at the service level, but nothing checks that a screen subscribes
  once and survives a rebuild — which is the bug class the split just fixed.

### 14. Decompose Settings properly

`settings_screen.dart` is still 1,575 lines and was deliberately left out of
the file split. Its bulk is one state class holding every controller and every
connection test, so per-section files mean handing all of it back in as
parameters and callbacks. That is a design change with real behavioural risk,
worth doing on purpose rather than as a move.

---

## Smaller items

- **"Add xpub wallet"** is the tooltip at `transactions_screen.dart:167`, but
  ypub and zpub have always worked and testnet keys work now too. Reword it to
  match what it actually accepts.
- **Transaction search/filter polish** — fuzzy matching, date-range picker.
- **Home screen widget** — stack balance + BTC price. Needs `home_widget` and
  an app group entitlement.
- **iCloud / local automatic backup** — complements the manual export in
  Settings → Data, which now takes a consistent `VACUUM INTO` snapshot and
  keeps a `.bak` on restore.
- **BTC price alerts** — threshold notification via
  `flutter_local_notifications`, which now actually fires on iOS.
- **Register the macOS bundle id** with Apple and switch `SecureKeyStore` to
  the data-protection keychain. Needed for any macOS distribution anyway; the
  comment in `secure_key_store.dart` explains why the file-based one is in use
  (the ad-hoc-signed target cannot carry the entitlement, so every write fails
  with `errSecMissingEntitlement`).
- **Verify a real request against each hosted provider.** Every wire format is
  unit tested against the documented shape, but nothing has run against a live
  endpoint with a real key — that needs four paid accounts.

---

## Known broken / unfinished

See **Next, items 1 and 2** — the second review pass found things that are
genuinely broken rather than merely imperfect: the macOS framework signing,
the discontinued on-device-model packages, and the native cancellation path.
The GPL/Syncfusion licence conflict in item 1 is a decision waiting on the
author, not a defect.

The only *dead* code is the Bitcoin data-source work in item 11, which is
waiting on a screen rather than failing.

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
