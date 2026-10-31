import 'package:flutter/material.dart';

import '../../../core/models/ai_backend_group.dart';
import '../../../core/models/ai_provider.dart';
import '../../../core/services/inference/cloud_backend.dart';
import '../../../core/services/inference/gemini_nano_backend.dart';
import '../../../core/services/inference/inference_backend.dart';
import '../../../core/services/inference/platform_llm_backend.dart';
import '../../../core/services/ollama_service.dart';
import '../../../main.dart' as app;
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/model_choices.dart';
import '../../../shared/utils/platform_utils.dart';
import '../../../shared/widgets/ai_privacy_disclosure.dart';
import 'import_consent_section.dart';
import 'on_device_ai_section.dart';
import 'settings_widgets.dart';

/// Settings → Servers → AI provider: the provider picker grouped by where
/// it runs, each provider's fields and connection test, the privacy
/// disclosure, and the on-device backends' status.
class AiProviderSection extends StatefulWidget {
  const AiProviderSection({super.key});

  @override
  State<AiProviderSection> createState() => _AiProviderSectionState();
}

class _AiProviderSectionState extends State<AiProviderSection> {
  // AI — active provider (mirrors persisted state)
  AiProvider _selectedProvider = AiProvider.ollama;

  // AI — Ollama
  late TextEditingController _ollamaUrlCtrl;
  List<String> _models = [];
  String? _selectedModel;
  bool _testingConnection = false;
  String? _connectionStatus;

  // AI — LM Studio
  late TextEditingController _lmStudioUrlCtrl;
  List<String> _lmStudioModels = [];
  String? _lmStudioSelectedModel;
  bool _testingLmStudio = false;
  String? _lmStudioStatus;

  // AI — Maple
  late TextEditingController _mapleUrlCtrl;
  late TextEditingController _mapleApiKeyCtrl;
  List<String> _mapleModels = [];
  String? _mapleSelectedModel;
  bool _testingMaple = false;
  String? _mapleStatus;

  // AI — hosted providers (Claude, ChatGPT, Gemini, Grok)
  //
  // Keyed by `CloudProvider.id` rather than four sets of fields, because the
  // four differ only in their wire format and that is `CloudBackend`'s problem,
  // not this screen's.
  final Map<String, TextEditingController> _cloudKeyCtrls = {};
  final Map<String, List<String>> _cloudModels = {};
  final Map<String, String> _cloudSelectedModel = {};
  final Map<String, bool> _cloudKeyVisible = {};
  String? _testingCloudId;
  String? _cloudStatus;

  @override
  void initState() {
    super.initState();
    // The privacy line under each AI provider is read from the saved URL.
    // Saving a new one rebuilt nothing, so after saving a public server's URL
    // the screen still said nothing leaves hardware you control.
    app.ollamaService.configChanges.addListener(_onAiConfigChange);
    // AI provider
    _selectedProvider = app.ollamaService.activeProvider;
    // Which on-device backends this hardware can offer, and — if one is already
    // selected — whether it can answer right now.
    _loadPlatformAvailability();
    if (_selectedProvider.isOnDevice) _refreshOnDeviceStatus();

    // Ollama
    _ollamaUrlCtrl = TextEditingController(text: app.ollamaService.baseUrl);
    _selectedModel = app.ollamaService.ollamaSelectedModel;

    // LM Studio
    _lmStudioUrlCtrl = TextEditingController(
      text: app.ollamaService.lmStudioBaseUrl,
    );
    _lmStudioSelectedModel = app.ollamaService.lmStudioSelectedModel;

    // Maple
    _mapleUrlCtrl = TextEditingController(text: app.ollamaService.mapleBaseUrl);
    _mapleApiKeyCtrl = TextEditingController(
      text: app.ollamaService.mapleApiKey,
    );
    _mapleSelectedModel = app.ollamaService.mapleSelectedModel;

    // Hosted providers. The key field is seeded from the keychain so an already
    // configured provider does not look empty, and the model list starts as the
    // static fallback so the dropdown is useful before any key is entered.
    for (final p in CloudProvider.values) {
      _cloudKeyCtrls[p.id] = TextEditingController(
        text: app.ollamaService.cloudApiKey(p),
      );
      _cloudModels[p.id] = p.fallbackModels;
      _cloudSelectedModel[p.id] = app.ollamaService.cloudModel(p);
      _cloudKeyVisible[p.id] = false;
    }
    _loadModels();
  }

  @override
  void dispose() {
    app.ollamaService.configChanges.removeListener(_onAiConfigChange);
    _ollamaUrlCtrl.dispose();
    _lmStudioUrlCtrl.dispose();
    _mapleUrlCtrl.dispose();
    _mapleApiKeyCtrl.dispose();
    for (final c in _cloudKeyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadModels() async {
    // Load models for the active provider on open.
    switch (_selectedProvider) {
      case AiProvider.ollama:
        final models = await app.ollamaService.listModels();
        if (mounted) setState(() => _models = models);
      case AiProvider.lmStudio:
        final models = await app.ollamaService.listModels();
        if (mounted) setState(() => _lmStudioModels = models);
      case AiProvider.maple:
        final models = await app.ollamaService.listModels();
        if (mounted) setState(() => _mapleModels = models);
      case AiProvider.claude:
      case AiProvider.chatGpt:
      case AiProvider.gemini:
      case AiProvider.grok:
        // Fetched live from the provider so a model released after this build
        // still shows up. Falls back to the static list inside the backend, so
        // this is safe to call with no key and no network.
        final p = _selectedProvider.cloudProvider!;
        final models = await app.ollamaService.listModels();
        if (mounted) setState(() => _cloudModels[p.id] = models);
      case AiProvider.appleIntelligence:
      case AiProvider.geminiNano:
        // No model list to fetch: Apple and Google each ship one model the OS
        // owns. Ask instead whether the backend can answer, which is the
        // equivalent question for these.
        await app.ollamaService.refreshOnDeviceReadiness();
        if (mounted) setState(() {});
    }
  }

  /// Re-derives the AI tab's visibility from `OllamaService`, which owns the
  /// rule. Every site here used to inline its own copy of it.
  void _refreshAiEnabled() =>
      app.aiEnabledNotifier.value = app.ollamaService.aiEnabled;

  Future<void> _onProviderChanged(AiProvider provider) async {
    setState(() {
      _selectedProvider = provider;
      // Belongs to whichever provider was selected when it was written.
      _cloudStatus = null;
    });
    await app.ollamaService.setActiveProvider(provider);
    // An on-device backend enables AI on mobile with no server at all, which
    // the old `isDesktop || isConnected` test could not express. A hosted
    // provider does the same once its key is in place — it needs no local
    // server either, so the tab must appear on a phone.
    _refreshAiEnabled();
    if (provider.isOnDevice) await _refreshOnDeviceStatus();
    if (provider.needsApiKey) await _loadModels();
  }

  /// Last availability report for the selected on-device backend, so the status
  /// panel can show the OS's own reason rather than a generic failure.
  BackendStatus? _onDeviceStatus;

  Future<void> _refreshOnDeviceStatus() async {
    final status = await app.ollamaService.checkStatus();
    if (mounted) setState(() => _onDeviceStatus = status);
  }

  /// Shows the URL actually saved, which can differ from what was typed: a
  /// bare `host:port` gains its scheme. Left alone when the field is blank,
  /// so clearing it does not refill it with the default.
  void _showEffectiveUrl(TextEditingController ctrl, String saved) {
    if (ctrl.text.trim().isNotEmpty && ctrl.text != saved) ctrl.text = saved;
  }

  void _onAiConfigChange() {
    if (mounted) setState(() {});
  }

  // ── Ollama ──────────────────────────────────────────────────────────────

  Future<void> _saveOllama() async {
    final url = _ollamaUrlCtrl.text.trim();
    await app.ollamaService.saveSettings(url: url, model: _selectedModel);
    _showEffectiveUrl(_ollamaUrlCtrl, app.ollamaService.baseUrl);
    if (url.isEmpty) {
      await app.ollamaService.setConnected(false);
      _refreshAiEnabled();
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ollama settings saved')));
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _connectionStatus = null;
    });
    await app.ollamaService.saveSettings(url: _ollamaUrlCtrl.text.trim());
    _showEffectiveUrl(_ollamaUrlCtrl, app.ollamaService.baseUrl);
    final ok = await app.ollamaService.isAvailable();
    if (!mounted) return;
    if (ok) {
      final models = await app.ollamaService.listModels();
      await app.ollamaService.setConnected(true);
      _refreshAiEnabled();
      if (mounted) {
        setState(() {
          _models = models;
          _testingConnection = false;
          _connectionStatus = 'Connected — ${models.length} model(s) found';
        });
      }
    } else {
      await app.ollamaService.setConnected(false);
      _refreshAiEnabled();
      if (!mounted) return;
      setState(() {
        _testingConnection = false;
        _connectionStatus =
            'Could not reach Ollama at ${_ollamaUrlCtrl.text.trim()}';
      });
    }
  }

  // ── LM Studio ───────────────────────────────────────────────────────────

  Future<void> _saveLmStudio() async {
    final url = _lmStudioUrlCtrl.text.trim();
    await app.ollamaService.saveLmStudioSettings(
      url: url,
      model: _lmStudioSelectedModel,
    );
    if (url.isEmpty) {
      await app.ollamaService.setConnected(false);
      _refreshAiEnabled();
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('LM Studio settings saved')));
    }
  }

  Future<void> _testLmStudioConnection() async {
    setState(() {
      _testingLmStudio = true;
      _lmStudioStatus = null;
    });
    final url = _lmStudioUrlCtrl.text.trim();
    await app.ollamaService.saveLmStudioSettings(url: url);
    _showEffectiveUrl(_lmStudioUrlCtrl, app.ollamaService.lmStudioBaseUrl);
    final ok = await app.ollamaService.isAvailable();
    if (!mounted) return;
    if (ok) {
      final models = await app.ollamaService.listModels();
      await app.ollamaService.setConnected(true);
      _refreshAiEnabled();
      if (mounted) {
        setState(() {
          _lmStudioModels = models;
          _testingLmStudio = false;
          _lmStudioStatus = 'Connected — ${models.length} model(s) found';
        });
      }
    } else {
      await app.ollamaService.setConnected(false);
      _refreshAiEnabled();
      if (!mounted) return;
      setState(() {
        _testingLmStudio = false;
        _lmStudioStatus = 'Could not reach LM Studio at $url';
      });
    }
  }

  // ── Hosted providers ────────────────────────────────────────────────────

  /// Save the key and model for [p].
  ///
  /// The key goes to the keychain, which can refuse — a locked device, a
  /// keyring daemon that is not running. That has to be surfaced rather than
  /// swallowed: the backend keeps working for this session either way, so a
  /// silent failure looks like success until the next launch, when the provider
  /// mysteriously has no key.
  Future<void> _saveCloud(CloudProvider p) async {
    final key = _cloudKeyCtrls[p.id]!.text.trim();
    final stored = await app.ollamaService.saveCloudSettings(
      p,
      model: _cloudSelectedModel[p.id],
      apiKey: key,
    );
    // A hosted provider needs nothing but a key, so saving one is enough to
    // bring the tab back on a phone.
    _refreshAiEnabled();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          stored
              ? '${p.label} settings saved'
              : 'Saved for this session only — this device would not let the '
                  'app store the key securely.',
        ),
        backgroundColor: stored ? null : AppColors.danger,
      ),
    );
  }

  Future<void> _testCloudConnection(CloudProvider p) async {
    setState(() {
      _testingCloudId = p.id;
      _cloudStatus = null;
    });
    await app.ollamaService.saveCloudSettings(
      p,
      apiKey: _cloudKeyCtrls[p.id]!.text.trim(),
    );

    final status = await app.ollamaService.checkStatus();
    if (!mounted) return;

    if (status.available) {
      final models = await app.ollamaService.listModels();
      await app.ollamaService.setConnected(true);
      _refreshAiEnabled();
      if (!mounted) return;
      setState(() {
        _cloudModels[p.id] = models;
        _testingCloudId = null;
        _cloudStatus = 'Connected — ${models.length} model(s) available';
      });
    } else {
      await app.ollamaService.setConnected(false);
      _refreshAiEnabled();
      if (!mounted) return;
      setState(() {
        _testingCloudId = null;
        _cloudStatus = status.detail ?? 'Could not reach ${p.host}.';
      });
    }
  }

  // ── Maple ───────────────────────────────────────────────────────────────

  Future<void> _saveMaple() async {
    final url = _mapleUrlCtrl.text.trim();
    final key = _mapleApiKeyCtrl.text.trim();
    await app.ollamaService.saveMapleSettings(
      url: url,
      model: _mapleSelectedModel,
      apiKey: key,
    );
    if (url.isEmpty) {
      await app.ollamaService.setConnected(false);
      _refreshAiEnabled();
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Maple settings saved')));
    }
  }

  Future<void> _testMapleConnection() async {
    setState(() {
      _testingMaple = true;
      _mapleStatus = null;
    });
    final url = _mapleUrlCtrl.text.trim();
    final key = _mapleApiKeyCtrl.text.trim();
    await app.ollamaService.saveMapleSettings(url: url, apiKey: key);
    _showEffectiveUrl(_mapleUrlCtrl, app.ollamaService.mapleBaseUrl);
    final ok = await app.ollamaService.isAvailable();
    if (!mounted) return;
    if (ok) {
      final models = await app.ollamaService.listModels();
      await app.ollamaService.setConnected(true);
      _refreshAiEnabled();
      if (mounted) {
        setState(() {
          _mapleModels = models;
          _testingMaple = false;
          _mapleStatus = 'Connected — ${models.length} model(s) found';
        });
      }
    } else {
      await app.ollamaService.setConnected(false);
      _refreshAiEnabled();
      if (!mounted) return;
      setState(() {
        _testingMaple = false;
        _mapleStatus = 'Could not reach Maple at $url';
      });
    }
  }

  /// Key field, model picker and connection test for a hosted provider.
  List<Widget> _cloudFields(ThemeData theme, CloudProvider cloud) {
    final ctrl = _cloudKeyCtrls[cloud.id]!;
    final models = _cloudModels[cloud.id] ?? cloud.fallbackModels;
    final selected = _cloudSelectedModel[cloud.id];
    final visible = _cloudKeyVisible[cloud.id] ?? false;
    final testing = _testingCloudId == cloud.id;
    // Advisory only. A key whose prefix has changed is still a valid key, and
    // refusing it would be far worse than accepting one that turns out to be
    // wrong — the connection test is what actually decides.
    return [
      // Rebuilt by the controller rather than by setState. Pasting a 100-char
      // key used to trigger a hundred full-screen rebuilds, and all the text
      // actually decides is the advisory helper line below.
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: ctrl,
        builder: (_, value, _) {
          // Advisory only. A key whose prefix has changed is still a valid
          // key, and refusing it would be far worse than accepting one that
          // turns out to be wrong — the connection test is what decides.
          final looksWrong =
              value.text.trim().isNotEmpty &&
              !value.text.trim().startsWith(cloud.keyPrefix);
          return TextField(
            controller: ctrl,
            obscureText: !visible,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: '${cloud.label} API key',
              hintText: '${cloud.keyPrefix}…',
              helperText:
                  looksWrong
                      ? '${cloud.label} keys usually start with '
                          '"${cloud.keyPrefix}".'
                      : 'Stored in this device\'s keychain, not in the app '
                          'database.',
              helperMaxLines: 2,
              suffixIcon: IconButton(
                icon: Icon(
                  visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 19,
                ),
                tooltip: visible ? 'Hide key' : 'Show key',
                onPressed:
                    () => setState(() => _cloudKeyVisible[cloud.id] = !visible),
              ),
            ),
          );
        },
      ),
      ApiKeyHelpLink(provider: _selectedProvider),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        // The saved model may not be in the live list — deprecated, filtered,
        // or only on a different tier — so it is added to the choices rather
        // than shown as no selection while it is still the one in use.
        initialValue: selected,
        decoration: const InputDecoration(labelText: 'Model'),
        hint: Text(cloud.defaultModel),
        items:
            modelChoices(
              models,
              selected,
            ).map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() => _cloudSelectedModel[cloud.id] = v);
        },
      ),
      const SizedBox(height: 12),
      if (_cloudStatus != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _cloudStatus!,
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  _cloudStatus!.startsWith('Connected')
                      ? context.legibleAccent(AppColors.success)
                      : context.legibleAccent(AppColors.danger),
            ),
          ),
        ),
      Wrap(
        // Wraps at a large text size rather than overflowing.
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: testing ? null : () => _testCloudConnection(cloud),
            icon:
                testing
                    ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.wifi_tethering_outlined, size: 18),
            label: const Text('Test key'),
          ),
          FilledButton(
            onPressed: () => _saveCloud(cloud),
            child: const Text('Save'),
          ),
        ],
      ),
    ];
  }

  /// Which backends to put in the picker on this device.
  ///
  /// The server-backed three are always offered — they depend on something the
  /// user sets up, not on the hardware. The on-device three are conditional,
  /// and the condition is asked of the platform rather than inferred from a
  /// version number: an iPhone 15 Pro on iOS 26 qualifies for Apple
  /// Intelligence while an iPhone 14 on a newer iOS does not.
  ///
  /// A backend already selected stays listed even if it has since become
  /// unavailable, so the picker cannot show an empty selection — the status
  /// panel below explains the problem instead.
  AiBackendCatalogue get _catalogue => AiBackendCatalogue(
    appleIntelligenceOffered: _appleLlm?.state.worthOffering ?? false,
    geminiNanoOffered: _nano?.state.worthOffering ?? false,
    keepSelected: _selectedProvider,
  );

  PlatformLlmAvailability? _appleLlm;
  GeminiNanoAvailability? _nano;

  /// Ask both platform backends once on open, so the picker knows what to show
  /// before the user touches anything.
  Future<void> _loadPlatformAvailability() async {
    final apple =
        PlatformLlmBackend.bridgedHere
            ? await PlatformLlmBackend.availability()
            : null;
    final nano =
        GeminiNanoBackend.bridgedHere
            ? await GeminiNanoBackend.availability()
            : null;
    if (mounted) {
      setState(() {
        _appleLlm = apple;
        _nano = nano;
      });
    }
  }

  /// Where [provider]'s data would go, or null when it stays on hardware the
  /// user controls.
  ///
  /// For the active provider this is derived from the URL actually configured,
  /// which is the only way to be right about Ollama and LM Studio: their
  /// `AiProvider.isPrivate` is hardcoded true while their endpoint is a
  /// free-text field. For any other provider it is the enum's fixed answer,
  /// which is correct for the hosted four and honest for an unconfigured
  /// self-hosted one.
  String? _recipientFor(AiProvider provider) =>
      provider == app.ollamaService.activeProvider
          ? app.ollamaService.activeDataRecipient
          : provider.dataRecipient;

  String? get _selectedRecipient => _recipientFor(_selectedProvider);

  /// The URL field for a provider whose server the user chooses.
  TextEditingController? _urlCtrlFor(AiProvider provider) => switch (provider) {
    AiProvider.ollama => _ollamaUrlCtrl,
    AiProvider.lmStudio => _lmStudioUrlCtrl,
    AiProvider.maple => _mapleUrlCtrl,
    _ => null,
  };

  String _providerDescription(AiProvider provider) {
    final recipient = _recipientFor(provider);
    return switch (provider) {
      // Derived, not asserted: the URL field decides. Saying "No data
      // leaves" for a server the user has pointed at the internet is the
      // one claim this app must never get wrong.
      AiProvider.lmStudio =>
        recipient == null
            ? 'A model running in LM Studio on this machine. No data leaves.'
            : 'LM Studio on the server you configured. Your financial figures '
                'are sent there to answer each question.',
      AiProvider.ollama =>
        recipient == null
            ? 'A model running on your own machine or one on your network. '
                'Your figures go no further than that machine.'
            : 'Ollama on the server you configured. Your financial figures '
                'are sent there to answer each question.',
      // Deliberately not "private, zero retention" as this once read. Maple
      // may well be both, but the app cannot verify either, and a claim it
      // cannot stand behind does not belong next to a backend that is, by
      // construction, off-device.
      AiProvider.maple =>
        'A hosted OpenAI-compatible endpoint you point at yourself.',
      AiProvider.appleIntelligence =>
        'The model already on this Mac or iPhone. No download, no key.',
      AiProvider.geminiNano =>
        'The model built into this phone, run by Android. No key.',
      AiProvider.claude ||
      AiProvider.chatGpt ||
      AiProvider.gemini ||
      AiProvider.grok =>
        'By far the most capable option, using your own '
            '${provider.cloudProvider!.company} API key. You pay '
            '${provider.cloudProvider!.company} directly for what you use.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SettingsSectionHeader('AI Provider'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pin the column to the full available width.
              //
              // Without this it sizes to its widest child, so the whole
              // picker slides horizontally as the selection changes:
              // a backend whose fields are narrow (the chips alone)
              // centres the block, while one with a full-width privacy
              // banner left-aligns it.
              const SizedBox(width: double.infinity),
              // Provider selector.
              //
              // Chips grouped by how the backend runs rather than one
              // flat Wrap: ten options in a single row of chips is a
              // wall, and the distinction that actually matters when
              // choosing — on my device, my server, or someone else's
              // — is invisible in a flat list. `_catalogue` also hides
              // the options this hardware cannot use, since a phone
              // that can never run Apple Intelligence is not helped by
              // a permanently dead row.
              for (final group in _catalogue.nonEmptyGroups) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    group.title.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: context.textSecondary,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in _catalogue.providersIn(group))
                      ChoiceChip(
                        label: Text(p.label),
                        selected: _selectedProvider == p,
                        onSelected: (_) => _onProviderChanged(p),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Text(
                _providerDescription(_selectedProvider),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.textSecondary,
                ),
              ),
              // The one claim in this app that must never be wrong. A
              // hosted backend sends the user's complete financial
              // picture to a third party, and that cannot sit under a
              // blanket "local-first" promise unqualified.
              // Gated on where the data would actually go, not on the
              // enum. `AiProvider.isPrivate` is hardcoded true for
              // Ollama and LM Studio, whose URLs are free-text fields
              // the user can point at a VPS — so this banner was
              // hidden for exactly the configuration that needs it.
              // `_selectedRecipient` is null when nothing leaves.
              if (_selectedRecipient != null) ...[
                const SizedBox(height: 8),
                AiPrivacyDisclosure(
                  provider: _selectedProvider,
                  recipient: _selectedRecipient,
                ),
              ],
              if (_urlCtrlFor(_selectedProvider) case final ctrl?)
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: ctrl,
                  builder:
                      (_, value, _) => TransportNote(
                        OllamaService.transportNoteFor(
                          _selectedProvider,
                          value.text,
                        ),
                      ),
                ),
              const SizedBox(height: 14),

              // ── Ollama fields ───────────────────────────────
              if (_selectedProvider == AiProvider.ollama) ...[
                TextField(
                  controller: _ollamaUrlCtrl,
                  decoration: InputDecoration(
                    labelText: 'Ollama base URL',
                    hintText:
                        PlatformUtils.isDesktop
                            ? 'http://localhost:11434'
                            : 'http://your-server:11434',
                  ),
                ),
                const SizedBox(height: 12),
                if (_models.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue:
                        modelChoices(
                              _models,
                              _selectedModel,
                            ).contains(_selectedModel)
                            ? _selectedModel
                            : null,
                    decoration: const InputDecoration(labelText: 'Model'),
                    hint: const Text('Select model'),
                    items:
                        modelChoices(_models, _selectedModel)
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _selectedModel = v),
                  )
                else
                  Text(
                    'No models loaded — test the connection first.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
                const SizedBox(height: 12),
                if (_connectionStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _connectionStatus!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            _connectionStatus!.startsWith('Connected')
                                ? context.legibleAccent(AppColors.success)
                                : context.legibleAccent(AppColors.danger),
                      ),
                    ),
                  ),
                Wrap(
                  // Wraps at a large text size rather than overflowing.
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testingConnection ? null : _testConnection,
                      icon:
                          _testingConnection
                              ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(
                                Icons.wifi_tethering_outlined,
                                size: 18,
                              ),
                      label: const Text('Test connection'),
                    ),
                    FilledButton(
                      onPressed: _saveOllama,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],

              // ── LM Studio fields ────────────────────────────
              if (_selectedProvider == AiProvider.lmStudio) ...[
                TextField(
                  controller: _lmStudioUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'LM Studio base URL',
                    hintText: 'http://localhost:1234/v1',
                  ),
                ),
                const SizedBox(height: 12),
                if (_lmStudioModels.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue:
                        _lmStudioModels.contains(_lmStudioSelectedModel)
                            ? _lmStudioSelectedModel
                            : null,
                    decoration: const InputDecoration(labelText: 'Model'),
                    hint: const Text('Select model'),
                    items:
                        _lmStudioModels
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                    onChanged:
                        (v) => setState(() => _lmStudioSelectedModel = v),
                  )
                else
                  Text(
                    'No models loaded — test the connection first.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
                const SizedBox(height: 12),
                if (_lmStudioStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _lmStudioStatus!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            _lmStudioStatus!.startsWith('Connected')
                                ? context.legibleAccent(AppColors.success)
                                : context.legibleAccent(AppColors.danger),
                      ),
                    ),
                  ),
                Wrap(
                  // Wraps at a large text size rather than overflowing.
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          _testingLmStudio ? null : _testLmStudioConnection,
                      icon:
                          _testingLmStudio
                              ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(
                                Icons.wifi_tethering_outlined,
                                size: 18,
                              ),
                      label: const Text('Test connection'),
                    ),
                    FilledButton(
                      onPressed: _saveLmStudio,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],

              // ── Maple fields ────────────────────────────────
              if (_selectedProvider == AiProvider.maple) ...[
                TextField(
                  controller: _mapleUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Maple proxy URL',
                    hintText: 'http://localhost:8080/v1',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _mapleApiKeyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API key',
                    hintText: 'maple_sk_...',
                  ),
                ),
                const SizedBox(height: 12),
                if (_mapleModels.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue:
                        _mapleModels.contains(_mapleSelectedModel)
                            ? _mapleSelectedModel
                            : null,
                    decoration: const InputDecoration(labelText: 'Model'),
                    hint: const Text('Select model'),
                    items:
                        _mapleModels
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _mapleSelectedModel = v),
                  )
                else
                  Text(
                    'No models loaded — test the connection first.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
                const SizedBox(height: 12),
                if (_mapleStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _mapleStatus!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            _mapleStatus!.startsWith('Connected')
                                ? context.legibleAccent(AppColors.success)
                                : context.legibleAccent(AppColors.danger),
                      ),
                    ),
                  ),
                Wrap(
                  // Wraps at a large text size rather than overflowing.
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testingMaple ? null : _testMapleConnection,
                      icon:
                          _testingMaple
                              ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(
                                Icons.wifi_tethering_outlined,
                                size: 18,
                              ),
                      label: const Text('Test connection'),
                    ),
                    FilledButton(
                      onPressed: _saveMaple,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],

              // ── Hosted provider fields ──────────────────────
              //
              // One block for all four. They differ only in their
              // endpoint and model list, both of which come off
              // `CloudProvider`, so there is nothing per-provider to
              // branch on here.
              if (_selectedProvider.cloudProvider case final cloud?)
                ..._cloudFields(theme, cloud),
            ],
          ),
        ),

        // ── On-device backends ──────────────────────────────────
        //
        // Rendered outside the padded Column above because each owns
        // its own layout: a status panel for the platform models, and
        // a full download catalogue for the local one.
        if (_selectedProvider == AiProvider.appleIntelligence ||
            _selectedProvider == AiProvider.geminiNano)
          PlatformModelStatus(
            detail: _onDeviceStatus?.detail ?? 'Checking with the system…',
            isReady: _onDeviceStatus?.available ?? false,
            onRecheck: _refreshOnDeviceStatus,
          ),
        // Offered whenever Nano is supported but not yet fetched —
        // this is the only place the download can be started from.
        if (_selectedProvider == AiProvider.geminiNano &&
            !(_onDeviceStatus?.available ?? true))
          GeminiNanoDownloadSection(onFinished: _refreshOnDeviceStatus),
        const ImportConsentSection(),

        const Divider(indent: 16, endIndent: 16),
      ],
    );
  }
}
