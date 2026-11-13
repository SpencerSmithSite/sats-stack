# TODO

**The single list of what is left to do.** If it is not here, it is either done
or nobody has decided to do it.

History lives elsewhere and is not duplicated into this file:

- [`AUDIT.md`](AUDIT.md): the open findings of the full scan on 2026-10-31, each
  with an ID and a status. Work through them from there. The earlier audits
  and the record of PRs #22–#54 are in git: `git show ef5b956:docs/AUDIT.md`.
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
- **When a fix lands, set its finding's Status in `AUDIT.md` to the PR**; when
  an item here lands, delete it. Open work is the open findings there plus
  what is below.

---

## Next

> **Second review pass, 2026-10-18.** Four independent reviews of the *current*
> code — data layer, AI/import, UI, and everything outside `lib/` — rather than
> a re-read of `AUDIT.md`. They found ~70 items, including two that would have
> shipped broken and three regressions introduced by the audit's own fixes.
> Those are fixed (in the earlier `AUDIT.md`, now in git). Everything below is what they found and is
> still open, in the order I would do it.

### 10. Decisions and upgrades the CI pass surfaced

- **Encrypt the database.** Decided 2026-10-20: yes. The design is in
  [`DATABASE_ENCRYPTION_PLAN.md`](DATABASE_ENCRYPTION_PLAN.md) — SQLCipher,
  a random key in the keychain, an in-place migration that copies drift's
  `user_version` by hand — with two decisions still open (the export format,
  and whether macOS waits for Developer ID signing).
- **`flutter_secure_storage` 11, after a release on 10.x.** 11 removes the
  Android migration out of EncryptedSharedPreferences, so a key that 10.x
  never moved becomes unreadable: an Android user going from a 9.x build
  straight to an 11.x build loses their API keys. Ship a release with 10.3
  (#152) first. 11 also finds iOS keychain items across accessibility
  classes, which overlaps the fallback in `SecureKeyStore`.
- **Built-in Kotlin on Android.** AGP 9.1.1 (#154) runs with
  `android.builtInKotlin=false`, as Flutter's own template does, because
  `file_picker` and `package_info_plus` still apply the Kotlin Gradle Plugin.
  Flutter warns that a future version will refuse that. Switch once they
  move: drop `kotlin-android` and the flag.
- **SQLite is downloaded at build time.** sqlite3 3's build hook (#155)
  fetches SQLite from the sqlite3.dart GitHub release, hash-checked, on every
  clean build. A GitHub outage failed CI once (2026-11-10). Caching the
  hook's download in CI, keyed on `pubspec.lock`, would stop that.
- **Calendar dates across timezones (audit D-11).** Deferred 2026-11-02.
  Picker and CSV dates are stored as local midnight, an instant, and read
  back in the device's current timezone, so after moving west a transaction
  on the 1st lands in the previous month. The fix is a schema migration that
  rewrites every `transactions.date`, `recurringAnchorDate` and
  `imported_transactions.date` as a calendar date. It also needs every
  reader changed (month ranges, recurring series, grouping, display) and a
  rule for xpub rows, which carry a real block time. Large and hard to undo
  for a bug that needs a move between timezones to show.

> Items 11–14 — the Bitcoin data-source picker, xpub batching, the named
> test gaps and the Settings split — are finished: PRs #51, #52 and #54.

> Item 15 — what the third review pass, 2026-10-21, left — is finished:
> PRs #22–#28 and #30–#50, recorded in the earlier `AUDIT.md` (git history).

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
- **Register the macOS bundle id** (`app.satsstack.SatsStack`, settled on
  2026-10-20) with Apple, and switch `SecureKeyStore` to the data-protection
  keychain. Needed for any macOS distribution anyway; the
  comment in `secure_key_store.dart` explains why the file-based one is in use
  (the ad-hoc-signed target cannot carry the entitlement, so every write fails
  with `errSecMissingEntitlement`). At the same time, turn on the hardened
  runtime (`ENABLE_HARDENED_RUNTIME = YES` for the macOS Runner's Release
  config), which notarisation needs (the rest of audit P-10).
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
