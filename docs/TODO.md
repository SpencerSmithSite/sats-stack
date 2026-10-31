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

> Items 11–14 were already tracked before the second pass. They are still
> open and still worth doing; they are simply less urgent than 1–10.

### 14. Decompose Settings properly

`settings_screen.dart` is still 1,575 lines and was deliberately left out of
the file split. Its bulk is one state class holding every controller and every
connection test, so per-section files mean handing all of it back in as
parameters and callbacks. That is a design change with real behavioural risk,
worth doing on purpose rather than as a move.

> Item 15 — what the third review pass, 2026-10-21, left — is finished:
> PRs #22–#28 and #30–#50, recorded in `AUDIT.md`.

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
- **Drop the unused media picker from iOS builds.** `file_picker` builds
  through Swift Package Manager, whose package hardcodes its media and audio
  pickers on, so every iOS build links DKImagePickerController, DKCamera,
  DKPhotoGallery, SDWebImage, SwiftyGif and TOCropViewController (~12 MB of
  debug object code) though the app only picks documents. Harmless at review:
  the camera and photo purpose strings are there for `image_picker` anyway,
  and the SDKs Apple lists ship privacy manifests. Removing them means
  replacing `file_picker` — `file_selector` opens files everywhere but cannot
  save on iOS or Android, so export there would need a share sheet instead.
- **Bitcoin Core.** `BitcoinNodeService` compiles and is referenced by
  nothing. Core keeps no address index, so it cannot be a wallet-history
  source (the picker offers Mempool/Esplora and Electrum); it is kept for
  broadcasting. Wire it up when sending is built, or delete it.
- **Try the Electrum path against a real electrs and Fulcrum.** It is tested
  end to end against a local fake server that speaks the protocol, including
  a self-signed TLS certificate, but not against either real implementation.
- **Verify a real request against each hosted provider.** Every wire format is
  unit tested against the documented shape, but nothing has run against a live
  endpoint with a real key — that needs four paid accounts.

---

## Known broken / unfinished

Nothing known to lose or misstate data is open. The decisions left are in
item 10.

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
