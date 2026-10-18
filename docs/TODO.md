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
  `flutter analyze --no-fatal-infos` and `flutter test` on every one.
- **Zero analyzer errors and warnings** is the standing bar. Info-level lints
  are tolerated (~40, mostly `withOpacity` deprecations) and CI does not fail
  on them, so clearing them is a deliberate task rather than something that
  happens on its own.
- **When an item lands, move it to `AUDIT.md`'s "Fixed" section**, so this file
  only ever shows open work.

---

## Next

### 1. Wire up the Bitcoin data-source picker

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

### 2. xpub scanning: off the UI isolate, and stop rescanning from zero

Two separate things, both in `xpub_service.dart`:

- Derivation runs on the UI isolate. A deep wallet means hundreds of pure-Dart
  `pointycastle` EC multiplications interleaved with network calls. Derive a
  window per hop inside `compute()`.
- There is no scan cursor, so every resync re-fetches from index 0 on both
  chains — 40+ requests for a wallet that has not changed, which is also what
  earns the rate limit that now (correctly) aborts the scan. Persist the
  highest used index per chain on the wallet row and resume from there,
  re-verifying only a gap-limit window. Needs a schema bump.

### 3. Close the named test gaps

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

### 4. Decompose Settings properly

`settings_screen.dart` is still 1,575 lines and was deliberately left out of
the file split. Its bulk is one state class holding every controller and every
connection test, so per-section files mean handing all of it back in as
parameters and callbacks. That is a design change with real behavioural risk,
worth doing on purpose rather than as a move.

### 5. Documentation that cannot be committed

`CLAUDE.md` is in `.gitignore`, so corrections to it cannot land through a PR.
It is currently wrong about two things:

- Flutter SDK: it says **3.41.5**; the installed version is **3.47.2**, which
  is what CI pins.
- DB schema version: it says **3**; `schemaVersion` is **7**.

Either edit it locally or untrack it so it can be maintained like everything
else.

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
- **Clear the ~40 info lints** (mostly `withOpacity` → `withValues`), then drop
  `--no-fatal-infos` from CI so they cannot come back.
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

Nothing is broken. The audit's open items are all fixed, and the only dead code
is the Bitcoin data-source work in item 1, which is waiting on a screen rather
than failing.

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
