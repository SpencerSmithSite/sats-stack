import '../services/inference/local_model_backend.dart';
import 'ai_provider.dart';

/// How the backends are grouped for the user.
///
/// Ten options is too many to present as one flat list, and the differences
/// that matter to someone choosing are not technical — they are "do I need to
/// set anything up?" and "does my money data leave this device?". The groups
/// answer both before the user reads a single provider name.
enum AiBackendGroup {
  onDevice(
    title: 'On this device',
    blurb: 'Nothing leaves your device. No account, no key, no server.',
  ),
  ownServer(
    title: 'Your own server',
    blurb: 'A model you run yourself, on this machine or your network.',
  ),
  hosted(
    title: 'Hosted — needs an API key',
    blurb: 'Powerful, but your financial data is sent to the provider.',
  );

  const AiBackendGroup({required this.title, required this.blurb});

  final String title;
  final String blurb;
}

/// Which backends this device can offer, grouped for display.
///
/// Shared by Settings and onboarding so the two cannot drift. They render it
/// differently — compact chips against full-width cards — but "what can this
/// hardware actually do" must be one answer, decided in one place.
class AiBackendCatalogue {
  const AiBackendCatalogue({
    required this.appleIntelligenceOffered,
    required this.geminiNanoOffered,
    required this.downloadableOffered,
    this.keepSelected,
  });

  /// Nothing on-device is offered until the platform has been asked. Used as
  /// the initial value while that check is in flight, so the picker never
  /// flashes a row it is about to remove.
  const AiBackendCatalogue.checking({AiProvider? keepSelected})
      : this(
          appleIntelligenceOffered: false,
          geminiNanoOffered: false,
          downloadableOffered: false,
          keepSelected: keepSelected,
        );

  /// Whether the platform reported Apple Intelligence as worth offering. Asked
  /// of the OS rather than inferred from a version number: an iPhone 15 Pro on
  /// iOS 26 qualifies while an iPhone 14 on a newer iOS does not.
  final bool appleIntelligenceOffered;
  final bool geminiNanoOffered;

  /// Whether the downloadable-model engine runs on this platform at all.
  final bool downloadableOffered;

  /// A backend that stays listed even if it has since become unavailable.
  ///
  /// Without this the picker can show an empty selection — the user chose Apple
  /// Intelligence, then switched it off in System Settings, and their own
  /// choice vanishes with no explanation. Keeping the row lets the status panel
  /// say what happened.
  final AiProvider? keepSelected;

  bool _offered(AiProvider p) => switch (p) {
        AiProvider.appleIntelligence => appleIntelligenceOffered,
        AiProvider.geminiNano => geminiNanoOffered,
        AiProvider.localModel => downloadableOffered,
        // Everything else depends on something the user sets up — a server, a
        // key — rather than on the hardware, so it is always offered.
        _ => true,
      };

  List<AiProvider> providersIn(AiBackendGroup group) {
    final all = switch (group) {
      AiBackendGroup.onDevice => const [
          AiProvider.appleIntelligence,
          AiProvider.geminiNano,
          AiProvider.localModel,
        ],
      AiBackendGroup.ownServer => const [
          AiProvider.ollama,
          AiProvider.lmStudio,
        ],
      AiBackendGroup.hosted => const [
          AiProvider.claude,
          AiProvider.chatGpt,
          AiProvider.gemini,
          AiProvider.grok,
          AiProvider.maple,
        ],
    };
    return all.where((p) => _offered(p) || p == keepSelected).toList();
  }

  /// The groups that have at least one row, in display order.
  ///
  /// On-device first: where a device has a built-in model it needs no key, no
  /// URL and no download, and that should be the obvious choice rather than
  /// something to discover after configuring something harder.
  List<AiBackendGroup> get nonEmptyGroups => AiBackendGroup.values
      .where((g) => providersIn(g).isNotEmpty)
      .toList();

  /// Every offered backend, flattened.
  List<AiProvider> get all =>
      [for (final g in AiBackendGroup.values) ...providersIn(g)];

  /// The backend to preselect for someone who has chosen nothing.
  ///
  /// A built-in model when the device has one — it works immediately, privately
  /// and for free. Otherwise Ollama, which is what the app has always defaulted
  /// to and is the honest "you will need to set something up" answer.
  AiProvider get suggestedDefault {
    if (appleIntelligenceOffered) return AiProvider.appleIntelligence;
    if (geminiNanoOffered) return AiProvider.geminiNano;
    return AiProvider.ollama;
  }

  /// True when the device can answer questions with nothing installed and no
  /// key — the case onboarding leads with.
  bool get hasZeroConfigOption =>
      appleIntelligenceOffered || geminiNanoOffered;

  /// Whether the downloadable engine runs on this platform.
  ///
  /// A separate probe from the two platform models, and deliberately not
  /// suppressed by them: having Apple Intelligence is a reason to *default* to
  /// it, not a reason to withhold the alternative. The built-in model is a
  /// fixed, modest one, and someone on a Mac with plenty of memory may well
  /// prefer a larger model they choose themselves.
  static bool get downloadableRunsHere => LocalModelChoice.runsHere;
}
