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
- **macOS bundle id and product name are still template placeholders.**
  `AppInfo.xcconfig:11` is `com.satsstack.satsStack` against iOS's
  `app.satsstack.SatsStack`, and `:8` makes the window title `sats_stack`.
  (The copyright string on `:14` is fixed.)

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

### 10. CI, lints and docs

- **CI compiles nothing native.** `flutter analyze` + `flutter test` on ubuntu
  cannot reach a single platform finding above: no Podfile is evaluated, no
  entitlement read, the Android manifest merge never runs, neither bridge is
  compiled. In value order: `dart format --set-exit-if-changed` (which needs
  a format-only PR first — 97 of the 126 Dart files would change, so mixing
  it into any other change buries that change),
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

- **A v1 → v8 migration against a fresh `onCreate`.** There is no generated
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
  `dashboard_rebuild_test.dart` now shows how to pump a whole screen against
  real services on an in-memory database (including the teardown drift needs),
  so the other four tabs can follow the same pattern.

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
