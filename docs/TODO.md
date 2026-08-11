# TODO

Near-term work, roughly in priority order. Longer design write-ups live beside
this file — see [AGENT_ACCESS_PLAN.md](AGENT_ACCESS_PLAN.md).

---

## ✅ 1. Cloud LLM providers — Claude, ChatGPT, Gemini, Grok

**Status: done.** `CloudProvider` + `CloudBackend` in
[`lib/core/services/inference/cloud_backend.dart`](../lib/core/services/inference/cloud_backend.dart),
four new `AiProvider` values, key storage moved to the keychain, Settings and
onboarding both reworked around a grouped chooser. What follows is the original
plan, kept because the notes explain *why* the shape is what it is.

**Two things landed differently from the plan:**

- **Model lists are fetched live**, not hardcoded. All four providers expose a
  models endpoint, so the picker queries it and falls back to a static list when
  there is no key or no network. A hardcoded list starts going stale the day it
  ships — which is exactly what happened to Council's.
- **macOS uses the file-based keychain**, not the data-protection one
  (`useDataProtectionKeyChain: false`). The data-protection keychain needs a
  `keychain-access-groups` entitlement, which needs the macOS bundle id
  (`com.satsstack.satsStack`) registered with Apple and a real provisioning
  profile — the target is currently ad-hoc signed. Until that is done, writes to
  the data-protection keychain fail at runtime with `errSecMissingEntitlement`.
  See the comment in `secure_key_store.dart`. **iOS is unaffected** — it is
  properly signed and uses the default.

### Follow-up worth doing

- **Register the macOS bundle id** and switch to the data-protection keychain.
  Needed anyway for any kind of macOS distribution.
- **Verify a real request against each provider.** Every wire format is unit
  tested against the documented shape, but nothing here has been run against a
  live endpoint with a real key — that needs four paid accounts.

---

<details>
<summary>Original plan (for the reasoning)</summary>

**Status:** not started · **Effort:** medium

Sats Stack currently offers Ollama, LM Studio, Maple, and the three on-device
backends. It has no first-class support for the major hosted models, which is
what most users will reach for. Council solved this with a `CloudProvider` enum
plus a `CloudBackend`, and the same shape fits here — the `InferenceBackend`
interface already exists and was built for exactly this.

### What to build

A `CloudProvider` enum carrying, per provider: id, display label, endpoint,
default model, model list, and the URL where the user creates a key (worth
showing in Settings — "where do I get this?" is the first question).

### Notes that will save time

- **Two wire formats, not four.** `OpenAiCompatBackend` already exists and
  already speaks OpenAI chat-completions with an optional bearer key. **OpenAI
  and Grok can reuse it as-is** — Grok's API is OpenAI-shaped. Only **Anthropic**
  and **Gemini** need their own request builders and stream decoders. Don't
  write four backends.
- **Use current model ids.** Council's list has aged (`claude-opus-4-8`,
  `gpt-4o`). For Anthropic the current family is Claude 5: `claude-opus-5`,
  `claude-sonnet-5`, `claude-haiku-4-5-20251001`, `claude-fable-5`. Check the
  others before copying anything across.
- **`isPrivate` must be `false`** for every cloud provider. The disclosure UI
  already exists and fires off that flag — see the banner under the picker in
  Settings, and `AiProvider.isPrivate`. This is the one claim in the app that
  must never be wrong: a hosted model receives the user's full financial
  picture.
- **`contextBudgetChars` should be large** (24k+, as Maple already is). The
  prompt builder sizes itself to this, so hosted models will automatically
  receive more spending detail than the on-device ones.
- **No official Dart SDK** exists for Anthropic or Google, so these speak REST
  directly. That is fine and is what Council does.

### ⚠️ Fix the API key storage at the same time

`AppConstants.settingMapleApiKey` puts the Maple key in the **`AppSettings`
table as plaintext SQLite** — the same file the agent-access plan wants to hand
to an MCP server. Adding four more providers multiplies that exposure.

Move keys to `flutter_secure_storage` (Keychain / Keystore) before or alongside
this work, and migrate the existing Maple key out of the database. Council
already does this: keys go to secure storage, everything else stays in ordinary
preferences.

</details>

---

## ✅ 2. Onboarding — reflect the full backend list

**Status: done.** The AI step is now a grouped, device-filtered chooser built on
`AiBackendCatalogue`
([`lib/core/models/ai_backend_group.dart`](../lib/core/models/ai_backend_group.dart)),
which Settings shares so the two cannot drift. On a device with a built-in model
the step preselects it and says so; the availability probe starts in `initState`
so the right option is already selected by the time the user pages to it.

<details>
<summary>Original plan</summary>

**Status:** not started · **Effort:** small–medium · **Depends on:** #1

The onboarding AI step still presents the original three server-backed
providers. It needs to become a real backend chooser:

- Group the options so the list stays readable at ~9 backends. The natural
  split is **on-device** (Apple Intelligence, Gemini Nano, downloaded model) /
  **your own server** (Ollama, LM Studio) / **hosted, needs a key** (Claude,
  ChatGPT, Gemini, Grok, Maple).
- Filter by device, the way Settings already does. `_offeredProviders` in
  `settings_screen.dart` is the reference: Apple Intelligence and Gemini Nano
  only appear where the platform reports them usable.
- Lead with the zero-configuration option where one exists. On a supported
  device Apple Intelligence or Nano needs no key, no URL and no download —
  that should be the obvious default rather than something to discover later.
- API key fields for the hosted providers, with the "get a key" link.
- The privacy line has to be **per-backend**. A blanket "everything stays on
  your device" is false the moment a hosted provider is selected.

`_ProviderConfigSection` in `onboarding_screen.dart` already branches on
`provider.isOnDevice` to hide the URL field and show a contextual note; extend
that rather than starting over.

</details>

---

## 3. Smaller items

- **Transaction search/filter polish** — fuzzy matching, date-range picker.
- **Home screen widget** — stack balance + BTC price. Needs `home_widget` and an
  app group entitlement.
- **iCloud / local automatic backup** — complements the manual export in
  Settings → Data.
- **BTC price alerts** — threshold notification via `flutter_local_notifications`.
- **Chart theming** — `fl_chart` is still hardcoded dark; respect
  `themeModeNotifier`.
- **TestFlight build** — process, not code.

---

## Known broken / unfinished (pre-existing)

Untracked and **not** committed, because two of them do not compile:

- `lib/core/services/bitcoin_node_service.dart` — references a
  `flutter_secure_storage` dependency that is not in `pubspec.yaml`, plus
  `AppConstants` keys that do not exist (`settingBitcoinRpcUrl`,
  `settingBitcoinRpcUser`, `settingBitcoinRpcPassword`, `defaultBitcoinRpcUrl`).
- `lib/core/services/electrum_service.dart` — same, for `settingElectrumHost`,
  `settingElectrumPort`, `settingElectrumSsl`, `defaultElectrumPort`.
- `lib/core/models/bitcoin_data_source.dart`,
  `lib/features/transactions/widgets/manage_wallets_sheet.dart`,
  `test/scripthash_test.dart` — appear complete but are untracked.

`flutter_secure_storage` is now a dependency (item #1), so the missing-package
half of the first two is resolved. Both still need their `AppConstants` keys
added before they will compile.
