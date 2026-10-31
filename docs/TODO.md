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
are referenced by nothing; they exist for this feature. `ElectrumService` has
no address → scripthash function yet: write one, and test it against the
genesis vector (`1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa` → scripthash
`8b01df4e368ea28f8dc0423bcf7a4923e3a12d307c875e47a0cfbf90b5c39161`). The old
`scripthash_test.dart` tested a copy defined inside itself, and was deleted.

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

### 15. Third review pass, 2026-10-21 — what is left

Everything else this pass found is fixed: PRs #22–#28, then #30–#47, each
recorded in `AUDIT.md` ("Third pass" and "Working through item 15"). Left:

**Native**
- `file_picker` 10 may still pull in DKCamera, CoreLocation and MediaPlayer
  through Swift Package Manager — check the built app's frameworks and
  privacy manifest, and drop the media picker if it is not needed.
- `assets/icons/` is bundled into the app though nothing loads it; it is the
  icon generator's source. Moving it out of `flutter: assets:` needs the
  generator configs checked first.

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
