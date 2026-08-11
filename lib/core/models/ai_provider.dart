import '../services/inference/cloud_backend.dart';

/// Which inference backend the user has selected.
///
/// The persisted identity of a backend. The behaviour lives in
/// `lib/core/services/inference/` — this enum only names the choice, so that
/// settings written by an older build still resolve and a value written on one
/// platform is recognised on another.
///
/// The values fall into three groups, which is how both Settings and onboarding
/// present them:
///
/// * **On device** — [appleIntelligence], [geminiNano], [localModel]. No URL and
///   no user-supplied model name; availability is owned by the OS rather than by
///   whether a server is reachable, which is why the picker asks each backend
///   for its own status instead of pinging a host.
/// * **Your own server** — [ollama], [lmStudio]. A host the user runs.
/// * **Hosted, needs a key** — [claude], [chatGpt], [gemini], [grok], [maple].
///   These send the user's financial data to a third party. See [isPrivate].
enum AiProvider {
  ollama,
  lmStudio,
  maple,
  appleIntelligence,
  geminiNano,
  localModel,
  claude,
  chatGpt,
  gemini,
  grok;

  /// The string persisted in `AppSettings`. Stable — changing one of these
  /// silently resets that user's choice back to Ollama.
  String get key => switch (this) {
        AiProvider.ollama => 'ollama',
        AiProvider.lmStudio => 'lmStudio',
        AiProvider.maple => 'maple',
        AiProvider.appleIntelligence => 'appleIntelligence',
        AiProvider.geminiNano => 'geminiNano',
        AiProvider.localModel => 'localModel',
        AiProvider.claude => 'claude',
        AiProvider.chatGpt => 'chatGpt',
        AiProvider.gemini => 'gemini',
        AiProvider.grok => 'grok',
      };

  /// Falls back to Ollama for an unknown value — a backend removed in a later
  /// build, most likely — rather than throwing on a settings read.
  static AiProvider fromKey(String? key) => switch (key) {
        'lmStudio' => AiProvider.lmStudio,
        'maple' => AiProvider.maple,
        'appleIntelligence' => AiProvider.appleIntelligence,
        'geminiNano' => AiProvider.geminiNano,
        'localModel' => AiProvider.localModel,
        'claude' => AiProvider.claude,
        'chatGpt' => AiProvider.chatGpt,
        'gemini' => AiProvider.gemini,
        'grok' => AiProvider.grok,
        _ => AiProvider.ollama,
      };

  /// Whether this backend runs entirely on the device, with no server to
  /// configure and no host to reach.
  bool get isOnDevice => switch (this) {
        AiProvider.appleIntelligence ||
        AiProvider.geminiNano ||
        AiProvider.localModel =>
          true,
        _ => false,
      };

  /// The hosted provider behind this choice, or null if there is none.
  ///
  /// Non-null exactly for the four major services. [maple] is hosted too but is
  /// an OpenAI-compatible endpoint the user points at themselves, so it keeps
  /// its URL field and is configured like a server rather than like a service.
  CloudProvider? get cloudProvider => switch (this) {
        AiProvider.claude => CloudProvider.anthropic,
        AiProvider.chatGpt => CloudProvider.openai,
        AiProvider.gemini => CloudProvider.gemini,
        AiProvider.grok => CloudProvider.xai,
        _ => null,
      };

  /// Whether this backend needs an API key before it can answer anything.
  bool get needsApiKey => cloudProvider != null;

  /// Name shown in the picker and in status lines.
  ///
  /// On the enum rather than at each call site because five screens were each
  /// switching over the same three names, and every one of them became a
  /// compile error the moment a backend was added. Adding one here is now the
  /// whole change.
  String get label => switch (this) {
        AiProvider.ollama => 'Ollama',
        AiProvider.lmStudio => 'LM Studio',
        AiProvider.maple => 'Maple',
        AiProvider.appleIntelligence => 'Apple Intelligence',
        AiProvider.geminiNano => 'Gemini Nano',
        AiProvider.localModel => 'Downloaded model',
        AiProvider.claude ||
        AiProvider.chatGpt ||
        AiProvider.gemini ||
        AiProvider.grok =>
          cloudProvider!.label,
      };

  /// The URL field's placeholder, or null when this backend has no server to
  /// point at.
  ///
  /// Null is the signal the settings and onboarding screens use to hide the URL
  /// field entirely. An on-device backend has nothing to point at, and a hosted
  /// service has one fixed endpoint the user must not be invited to edit —
  /// showing either an empty "Server URL" box invites them to fill in something
  /// that will be ignored, or worse, to send their financial data somewhere
  /// they mistyped.
  String? get defaultUrl => switch (this) {
        AiProvider.ollama => 'http://localhost:11434',
        AiProvider.lmStudio => 'http://localhost:1234/v1',
        AiProvider.maple => 'http://localhost:8080/v1',
        AiProvider.appleIntelligence ||
        AiProvider.geminiNano ||
        AiProvider.localModel ||
        AiProvider.claude ||
        AiProvider.chatGpt ||
        AiProvider.gemini ||
        AiProvider.grok =>
          null,
      };

  /// Whether answers are generated without anything leaving the device.
  ///
  /// Duplicated from the backend's own `isPrivate` so the picker can label a
  /// row it has not constructed a backend for. Keep the two in step: this is
  /// the one claim in the app that must never be wrong.
  ///
  /// [ollama] and [lmStudio] count as private: the host is hardware the user
  /// controls, whether that is this machine or a box on their LAN. Every hosted
  /// service does not, including [maple].
  bool get isPrivate => this != AiProvider.maple && cloudProvider == null;

  /// Who receives the user's financial data, for the privacy disclosure.
  ///
  /// Null when nothing leaves the device. Named rather than left vague because
  /// "sent to a server" is not a disclosure — the user needs to know *whose*.
  String? get dataRecipient => switch (this) {
        AiProvider.maple => 'the Maple server you configured',
        _ => cloudProvider == null
            ? null
            : '${cloudProvider!.company} (${cloudProvider!.host})',
      };
}
