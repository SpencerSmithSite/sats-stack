import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart' as app;
import '../../core/models/ai_backend_group.dart';
import '../../core/models/ai_provider.dart';
import '../../core/services/inference/cloud_backend.dart';
import '../../core/services/inference/gemini_nano_backend.dart';
import '../../core/services/inference/platform_llm_backend.dart';
import '../../shared/constants/app_constants.dart';
import '../../core/database/database.dart';
import 'pages/ai_provider_page.dart';
import 'pages/bitcoin_server_page.dart';
import 'pages/currency_page.dart';
import 'pages/ready_page.dart';
import 'pages/welcome_page.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  // Config chosen during onboarding
  String _currency = 'USD';
  ThemeMode _themeMode = ThemeMode.dark;
  AiProvider _aiProvider = AiProvider.ollama;
  late final TextEditingController _esploraCtrl;
  late final TextEditingController _aiUrlCtrl;
  late final TextEditingController _mapleApiKeyCtrl;

  /// API key field per hosted provider, keyed by [CloudProvider.id].
  final Map<String, TextEditingController> _cloudKeyCtrls = {
    for (final p in CloudProvider.values) p.id: TextEditingController(),
  };

  /// What this device can offer. Starts empty and is replaced once the platform
  /// has answered, so no on-device row is shown and then withdrawn.
  AiBackendCatalogue _catalogue = const AiBackendCatalogue.checking();

  /// Whether the user has picked a backend themselves.
  ///
  /// Until they have, the selection tracks [AiBackendCatalogue.suggestedDefault]
  /// so a device with a built-in model lands on it. After they have, their
  /// choice is theirs — the availability check completing must not silently
  /// move the selection out from under them.
  bool _aiProviderTouched = false;

  static const _pageCount = 8;

  void _next() {
    if (_page < _pageCount - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _previous() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    // Save currency
    app.currencyNotifier.value = _currency;
    await app.db
        .into(app.db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingCurrency,
            value: _currency,
          ),
        );
    app.btcPriceService.switchCurrency(_currency);

    // Save theme
    app.themeModeNotifier.value = _themeMode;
    final themeValue = switch (_themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await app.db
        .into(app.db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingThemeMode,
            value: themeValue,
          ),
        );

    // Save Bitcoin/Esplora server (empty = use default)
    await app.xpubService.saveSettings(url: _esploraCtrl.text.trim());
    await app.btcPriceService.loadSettings();

    // Save AI provider selection + connection details
    await app.ollamaService.setActiveProvider(_aiProvider);
    final trimmedUrl = _aiUrlCtrl.text.trim();
    final trimmedKey = _mapleApiKeyCtrl.text.trim();
    switch (_aiProvider) {
      case AiProvider.ollama:
        await app.ollamaService.saveSettings(
          url:
              trimmedUrl.isNotEmpty
                  ? trimmedUrl
                  : AppConstants.defaultOllamaUrl,
        );
      case AiProvider.lmStudio:
        await app.ollamaService.saveLmStudioSettings(
          url:
              trimmedUrl.isNotEmpty
                  ? trimmedUrl
                  : AppConstants.defaultLmStudioUrl,
        );
      case AiProvider.maple:
        await app.ollamaService.saveMapleSettings(
          url:
              trimmedUrl.isNotEmpty ? trimmedUrl : AppConstants.defaultMapleUrl,
          apiKey: trimmedKey.isNotEmpty ? trimmedKey : null,
        );
      case AiProvider.claude:
      case AiProvider.chatGpt:
      case AiProvider.gemini:
      case AiProvider.grok:
        final cloud = _aiProvider.cloudProvider!;
        final cloudKey = _cloudKeyCtrls[cloud.id]!.text.trim();
        // Only written when there is something to write: passing an empty key
        // would clear a key an earlier run had saved, and someone re-running
        // onboarding from Settings → About should not lose their credentials
        // by walking past this page.
        if (cloudKey.isNotEmpty) {
          await app.ollamaService.saveCloudSettings(cloud, apiKey: cloudKey);
        }
      case AiProvider.appleIntelligence:
      case AiProvider.geminiNano:
      case AiProvider.localModel:
        // Nothing to persist beyond the provider choice itself, which
        // `setActiveProvider` above already wrote. The downloadable model still
        // has to be fetched — Settings is where that happens, since it needs
        // progress and a size the onboarding flow has no room for.
        break;
    }
    // One rule, owned by OllamaService: an on-device backend needs no server,
    // and a hosted one needs only a key. Settings had its own copy of this
    // that was missing the hosted term.
    app.aiEnabledNotifier.value = app.ollamaService.aiEnabled;

    // Mark onboarding complete, in the database and in the notifier the
    // router's redirect reads. Both, or the redirect sends the user straight
    // back here.
    await app.db
        .into(app.db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingOnboardingComplete,
            value: 'true',
          ),
        );
    app.onboardingCompleteNotifier.value = true;

    if (mounted) context.go('/dashboard');
  }

  @override
  void initState() {
    super.initState();
    _esploraCtrl = TextEditingController();
    _aiUrlCtrl = TextEditingController(text: AppConstants.defaultOllamaUrl);
    _mapleApiKeyCtrl = TextEditingController();
    _loadPlatformAvailability();
  }

  /// Ask both platform backends what this hardware can do.
  ///
  /// Started in `initState` rather than when the AI page scrolls into view:
  /// there are six pages before it, which is far more time than the check
  /// needs, so by the time the user arrives the right option is already
  /// selected instead of appearing a beat later.
  Future<void> _loadPlatformAvailability() async {
    final apple =
        PlatformLlmBackend.bridgedHere
            ? await PlatformLlmBackend.availability()
            : null;
    final nano =
        GeminiNanoBackend.bridgedHere
            ? await GeminiNanoBackend.availability()
            : null;
    if (!mounted) return;
    setState(() {
      _catalogue = AiBackendCatalogue(
        appleIntelligenceOffered: apple?.state.worthOffering ?? false,
        geminiNanoOffered: nano?.state.worthOffering ?? false,
        downloadableOffered: AiBackendCatalogue.downloadableRunsHere,
      );
      if (!_aiProviderTouched) {
        _aiProvider = _catalogue.suggestedDefault;
        _aiUrlCtrl.text = _aiProvider.defaultUrl ?? '';
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _esploraCtrl.dispose();
    _aiUrlCtrl.dispose();
    _mapleApiKeyCtrl.dispose();
    for (final c in _cloudKeyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const WelcomePage(),
                  const FeaturesPage(),
                  const TourPage(),
                  CurrencyPage(
                    selected: _currency,
                    onChanged: (c) => setState(() => _currency = c),
                  ),
                  ThemePage(
                    selected: _themeMode,
                    onChanged: (m) {
                      setState(() => _themeMode = m);
                      app.themeModeNotifier.value = m;
                    },
                  ),
                  BitcoinServerPage(controller: _esploraCtrl),
                  AiProviderPage(
                    catalogue: _catalogue,
                    selected: _aiProvider,
                    onChanged: (p) {
                      setState(() {
                        _aiProvider = p;
                        _aiProviderTouched = true;
                      });
                      // Empty for the on-device and hosted backends, neither of
                      // which has a server the user should be pointing at — the
                      // page hides the URL field rather than prefilling it with
                      // something meaningless.
                      _aiUrlCtrl.text = p.defaultUrl ?? '';
                    },
                    urlController: _aiUrlCtrl,
                    apiKeyController: _mapleApiKeyCtrl,
                    cloudKeyControllers: _cloudKeyCtrls,
                  ),
                  const ReadyPage(),
                ],
              ),
            ),
            BottomBar(
              page: _page,
              pageCount: _pageCount,
              onNext: _next,
              onPrevious: _previous,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pages ─────────────────────────────────────────────────────────────────────

/// The backend chooser.
///
/// Ten options grouped three ways rather than one flat list of cards. The
/// grouping is not cosmetic: "on this device" versus "hosted" is the single
/// most consequential thing about the choice, and burying it in the body text
/// of ten similar-looking cards means nobody reads it. Which rows appear at all
/// comes from [AiBackendCatalogue], so a phone that can never run Apple
/// Intelligence is not offered it.

/// One selectable backend row.

/// The bordered info/warning strip used across the AI configuration pages.
///
/// Extracted so the on-device backends, which have no fields to show, can still
/// say something in the same visual language as the rest of the step rather
/// than leaving the page blank.

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

// ── Bottom bar ────────────────────────────────────────────────────────────────
