/// Which inference backend the user has selected.
///
/// The persisted identity of a backend. The behaviour lives in
/// `lib/core/services/inference/` — this enum only names the choice, so that
/// settings written by an older build still resolve and a value written on one
/// platform is recognised on another.
///
/// [appleIntelligence], [geminiNano] and [localModel] are on-device: they have
/// no URL and no user-supplied model name, and their availability is owned by
/// the OS rather than by whether a server is reachable. That is why the picker
/// asks each backend for its own status instead of pinging a host.
enum AiProvider {
  ollama,
  lmStudio,
  maple,
  appleIntelligence,
  geminiNano,
  localModel;

  /// The string persisted in `AppSettings`. Stable — changing one of these
  /// silently resets that user's choice back to Ollama.
  String get key => switch (this) {
        AiProvider.ollama => 'ollama',
        AiProvider.lmStudio => 'lmStudio',
        AiProvider.maple => 'maple',
        AiProvider.appleIntelligence => 'appleIntelligence',
        AiProvider.geminiNano => 'geminiNano',
        AiProvider.localModel => 'localModel',
      };

  /// Falls back to Ollama for an unknown value — a backend removed in a later
  /// build, most likely — rather than throwing on a settings read.
  static AiProvider fromKey(String? key) => switch (key) {
        'lmStudio' => AiProvider.lmStudio,
        'maple' => AiProvider.maple,
        'appleIntelligence' => AiProvider.appleIntelligence,
        'geminiNano' => AiProvider.geminiNano,
        'localModel' => AiProvider.localModel,
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

  /// Name shown in the picker and in status lines.
  ///
  /// On the enum rather than at each call site because five screens were each
  /// switching over the same three names, and every one of them became a
  /// compile error the moment a backend was added. Adding the sixth here is now
  /// the whole change.
  String get label => switch (this) {
        AiProvider.ollama => 'Ollama',
        AiProvider.lmStudio => 'LM Studio',
        AiProvider.maple => 'Maple',
        AiProvider.appleIntelligence => 'Apple Intelligence',
        AiProvider.geminiNano => 'Gemini Nano',
        AiProvider.localModel => 'Downloaded model',
      };

  /// The URL field's placeholder, or null when this backend has no server.
  ///
  /// Null is the signal the settings and chat screens use to hide the URL and
  /// model fields entirely — an on-device backend has nothing to point at, and
  /// showing it an empty "Server URL" box invites the user to fill in something
  /// that will be ignored.
  String? get defaultUrl => switch (this) {
        AiProvider.ollama => 'http://localhost:11434',
        AiProvider.lmStudio => 'http://localhost:1234/v1',
        AiProvider.maple => 'http://localhost:8080/v1',
        AiProvider.appleIntelligence ||
        AiProvider.geminiNano ||
        AiProvider.localModel =>
          null,
      };

  /// Whether answers are generated without anything leaving the device.
  ///
  /// Duplicated from the backend's own `isPrivate` so the picker can label a
  /// row it has not constructed a backend for. Keep the two in step: this is
  /// the one claim in the app that must never be wrong.
  bool get isPrivate => this != AiProvider.maple;
}
