# Database encryption — plan

**Status:** proposed 2026-10-20, for review before any code. Decided: the
database should be encrypted. Not yet decided: the two questions in
[Decisions needed](#decisions-needed).

The database holds every transaction, balance, budget and wallet the user has
entered, and the xpubs that reveal their whole Bitcoin history. Today it is
plain SQLite, protected only by the device's own storage encryption. Onboarding
used to claim it was encrypted; that copy was corrected on 2026-10-20, and this
is the plan for making the claim true.

Facts marked **[verified]** were checked against this repo or the installed
packages while writing this. Facts marked **[to verify]** are what I expect from
the libraries' documentation and must be confirmed in the first commit, before
anything depends on them.

---

## What "encrypted" will mean

- The database file on disk is AES-256 encrypted with SQLCipher. A copied file
  (an iCloud or Time Machine backup, a stolen laptop's disk, an Android cloud
  backup) is unreadable without the key.
- The key is 32 random bytes, generated on the device and stored in the
  platform keychain/keystore through the existing `SecureKeyStore`. The user
  never types or sees it. (A user passphrase is possible later; see
  [Not in scope](#not-in-scope).)
- It does **not** protect against someone who can run code as the user on an
  unlocked device: the app can open the database, so can they. That is the
  same threat model as every keychain-backed app and should be stated as such.

## Design

### 1. Library: SQLCipher replaces the bundled SQLite

- Today: `drift 2.31.0`, `drift_flutter 0.2.8`, `sqlite3 2.9.4`,
  `sqlite3_flutter_libs 0.5.42` **[verified]**.
- `sqlcipher_flutter_libs` (same author as `sqlite3`) bundles SQLCipher in
  place of SQLite. The two cannot both be linked: both export the `sqlite3_*`
  symbols **[to verify — the drift docs say so]**.
- `drift_flutter` depends on `sqlite3_flutter_libs` **[verified: its pubspec
  requires `^0.5.24`]**, so it has to go. Its job here is small: open the file
  on a background isolate at the path `databaseFile()` already resolves. That
  becomes `NativeDatabase.createInBackground(file, setup: …, isolateSetup: …)`
  — about thirty lines, and the `setup` hook is where the key is applied
  **[verified: `DatabaseSetup` is documented for exactly this]**.
- Stay on `sqlite3` 2.x for this change. `sqlite3` 3.x replaces the
  `*_flutter_libs` packages with build hooks; that is a separate upgrade, and
  mixing it in would make a failure impossible to attribute.

### 2. The key

- Created on first launch after this ships: `Random.secure()` → 32 bytes → hex,
  written with `SecureKeyStore` under the id `database`.
- Applied as a raw key, `PRAGMA key = "x'<64 hex chars>'"`, which skips
  SQLCipher's passphrase derivation (~256k PBKDF2 rounds per open) because the
  key is already random.
- Checked immediately with `SELECT count(*) FROM sqlite_master`: a wrong key
  does not fail at `PRAGMA key`, only at the first read.
- Keychain access is `first_unlock_this_device` on iOS and `first_unlock` on
  macOS (iOS changed 2026-10-29; see `secure_key_store.dart`), so anything
  that opens the database after the first unlock since boot works. Nothing in
  the app runs before that today.

**The rule that matters most: never create a key when an encrypted database
already exists.** If the key cannot be read but the file is encrypted, writing
a new key would lock the user out of their own data for good. That case gets
its own screen (below) instead.

### 3. Migrating the existing plaintext database

Every current user has a plaintext file, so the first launch after this ships
encrypts it in place.

1. Detect plaintext by its 16-byte header, `SQLite format 3\0`. An encrypted
   file's header is random. (`_looksLikeSqlite` in Settings already reads this.)
2. Open the plaintext file with SQLCipher and an empty key (SQLCipher reads
   plaintext databases that way **[to verify]**).
3. `ATTACH DATABASE '<db>.encrypting' AS enc KEY "x'…'"`, then
   `SELECT sqlcipher_export('enc')`, then `DETACH`.
4. **Copy `user_version` by hand.** `sqlcipher_export` does not copy it
   **[to verify — documented as such]**, and drift reads it to decide which
   migrations to run. Skipping this step would make drift treat the database
   as brand new and run `onCreate` against existing tables — the worst
   possible outcome, so it gets its own test.
5. Open `<db>.encrypting` with the key, and check every table's row count
   against the plaintext file.
6. Rename the plaintext file to `<db>.pre-encryption`, then
   `<db>.encrypting` to `<db>`. Both renames are on the same volume, so each
   one is atomic.
7. On the next successful launch, delete `<db>.pre-encryption`. One launch
   later, not straight away, so a fault in the new file can be recovered from.

Crash safety comes from the order. At startup, if `<db>` is missing but
`<db>.pre-encryption` exists, the swap was interrupted after step 6's first
rename, so finish it or roll it back. A stray `<db>.encrypting` with a
plaintext `<db>` means step 5 never passed: delete it and start again.

Deleting the plaintext copy does not securely erase it from flash storage; no
app can promise that. The README's privacy section will say so.

### 4. Export and import (Settings → Data)

Today, export is `VACUUM INTO` a user-chosen path **[verified]**. On an
encrypted database that produces a file encrypted with this device's key, which
is useless after a reinstall or on another device: the key never leaves the
keychain. So export has to change, and this is the first decision below.

- **Recommended: a password-protected export.** The user sets a password at
  export time. The backup is written with `sqlcipher_export` into an attached
  database keyed from that password, this time *with* PBKDF2, because a human
  chose it. Import asks for the password, then re-keys the file to the
  device's own key. The backup file is the copy most likely to end up
  somewhere public — a cloud drive, an email — so it is the one that most
  needs encrypting.
- Import still accepts a **plaintext** backup made before this ships, detected
  by its header, so existing backups keep working.
- `replaceDatabaseFile` and its relaunch dialog stay as they are; only what is
  copied in changes.

### 5. Android backup

**Done separately, 2026-10-20** (see `AUDIT.md`): cloud backup now excludes
the database and the secure-storage file, and device transfer excludes the
secure-storage file. When encryption ships, device transfer must exclude the
database as well — a transferred encrypted file arrives without its key.

The manifest does not set `android:allowBackup` **[verified]**, so Android
Auto Backup is on by default. Before the fix above, that sent the plaintext
database and the API keys to the user's Google Drive backup (the keys in
`flutter_secure_storage`'s EncryptedSharedPreferences, whose Keystore key does
not travel, so a restore brought back a file that could not be read). After
encryption, a restored database would be unreadable for the same reason.

Fix both together with `dataExtractionRules` (Android 12+) and
`fullBackupContent` (Android 11 and earlier). Exclude the secure-storage
preferences file and the database from cloud backup, and keep device-to-device
transfer. The supported way to move to a new phone is the export described
above. This deserves its own commit, ahead of encryption, because it fixes a
leak that exists right now.

### 6. When the database cannot be opened

A full-screen state in place of the app, never a crash and never a silently
empty database:

- **Key unreadable, file encrypted.** "Sats Stack can't unlock your data on
  this device." Two options: *Try again* (the keychain may simply be locked),
  and *Restore from a backup*, which leads to Import. No option to create a
  fresh key while the file is still there.
- **Key readable, but wrong.** The same screen. The likely cause is a database
  restored without its key.
- *Start over* (delete everything) is offered only behind a typed
  confirmation, and only after both options above.

### 7. Tests

- `flutter test` runs on the host. With `sqlcipher_flutter_libs`, the host
  needs SQLCipher too: `brew install sqlcipher` locally, and
  `apt-get install libsqlcipher-dev` in CI, loaded through
  `open.overrideFor` in a shared test setup **[to verify]**. Every existing
  database test then runs against the real library rather than a stand-in.
- New tests: a migration from a plaintext fixture at **every schema version
  v1–v8**, checking `user_version`, row counts and a sample of values; an
  interrupted migration at each step; a wrong key; a missing key with an
  encrypted file (no new key is written); and export/import round trips for
  both a password-protected and a legacy plaintext backup.
- On devices: the migration on a real iPhone, Android phone and Mac with a
  copy of a real database, before the PR is merged.

### 8. Export compliance

SQLCipher is encryption the app ships itself, not the operating system's, so
`ITSAppUsesNonExemptEncryption` can no longer honestly be `false`.
Encrypting the user's own data at rest in a consumer app usually falls under
the US "mass market" provisions, which typically means answering *yes* in App
Store Connect and filing an annual self-classification report. **This is not
legal advice:** check the current Apple and BIS guidance, and decide, before
the first build with SQLCipher is uploaded. The Info.plist comment already
says this key has to be revisited.

### 9. Cost

- Roughly 1–3 MB more per platform for the SQLCipher library **[to verify]**.
- Typically 5–15% slower queries, which is irrelevant at this database's size.
  Opening is fast because the key is raw.
- Order of work, each step its own commit and the first two shippable alone:
  Android backup rules → drop `drift_flutter` (still plain SQLite) → key and
  SQLCipher with migration → export/import → the error screen.

---

## Found since, 2026-10-21 (for whoever picks this up)

Facts the re-audit turned up that bear on the design. They are not decisions;
the two below are still on hold.

- **`sqlcipher_flutter_libs` is end of life.** `flutter pub outdated` lists
  its latest as `0.7.0+eol` (and `sqlite3_flutter_libs` as `0.6.0+eol`), with
  `sqlite3` 3.x resolvable. Section 1's "stay on `sqlite3` 2.x" would build on
  a package that gets no fixes. In `sqlite3` 3.x SQLCipher is chosen through
  build hooks, so the 3.x / `drift_flutter` 0.3 move probably comes first.
- **The keychain class decides what an iCloud backup protects.** The key
  would be stored as `first_unlock`, which is not a `…ThisDeviceOnly` class,
  so it travels in the same encrypted iCloud or Finder backup as the
  database — contrary to "What encrypted will mean". `first_unlock_this_device`
  makes a backup useless without an export; the current class makes it
  portable but unprotected. Either way it should be chosen and written down,
  and the restore paths tested. (The comment justifying `first_unlock` cited a
  background refresh; the app has no background execution at all. The API
  keys moved to `first_unlock_this_device` on iOS on 2026-10-29 for that
  reason; the database key still needs its own decision.)
- **Export compliance (section 8):** the annual self-classification report
  was removed for most mass-market items by the March 2021 BIS rule. Check
  current guidance rather than relying on that sentence.
- **Agent access** ([`AGENT_ACCESS_PLAN.md`](AGENT_ACCESS_PLAN.md)) has an
  external binary reading the SQLite file, which an encrypted database with a
  keychain-held key does not allow. One of the two designs has to give.

## Decisions needed

1. **What should export produce?** A password-protected backup (recommended),
   or a plaintext one with a warning that it is unencrypted?
2. **When should macOS get it?** The macOS app is still ad-hoc signed and uses
   the file-based keychain. Its access rules are tied to the code signature,
   so every rebuild may ask permission to read the key, or refuse. That is a
   nuisance in development, not a risk to data, since nothing writes a new key
   when one exists. Options: ship on all three platforms together and accept
   the prompts until Developer ID signing lands (recommended), or ship on iOS
   and Android first.

## Not in scope

- A user passphrase or biometric unlock in front of the database. It would
  protect against someone with the unlocked device, but it makes forgetting
  the passphrase mean losing everything. If wanted, it layers on top of this
  design by wrapping the random key.
- Encrypting `AppSettings` separately: it is in the database, so it is
  covered.
- Moving to `sqlite3` 3.x and its build hooks.
