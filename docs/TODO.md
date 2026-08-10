# TODO

Near-term work, roughly in priority order. Longer design write-ups live beside
this file — see [AGENT_ACCESS_PLAN.md](AGENT_ACCESS_PLAN.md).

---

## 1. Cloud LLM providers — Claude, ChatGPT, Gemini, Grok

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

---

## 2. Onboarding — reflect the full backend list

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

Adding `flutter_secure_storage` for item #1 would resolve half of the first two.
