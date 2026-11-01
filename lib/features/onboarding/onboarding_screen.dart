import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/models/ai_backend_group.dart';
import '../../core/models/ai_provider.dart';
import '../../core/services/inference/cloud_backend.dart';
import '../../core/services/inference/gemini_nano_backend.dart';
import '../../core/services/inference/platform_llm_backend.dart';
import '../../main.dart' as app;
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/url_utils.dart';
import 'pages/ai_provider_page.dart';
import 'pages/bitcoin_server_page.dart';
import 'pages/currency_page.dart';
import 'pages/ready_page.dart';
import 'pages/welcome_page.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.revisit = false});

  /// Opened from Settings → About rather than on first launch.
  ///
  /// Said by the route, because the onboarding flag cannot say it: About
  /// clears that flag, so a revisit read it as a first run, and the provider
  /// check replaced the user's AI provider and its URL with a suggestion,
  /// which Get Started then saved (audit U-1).
  final bool revisit;

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
  static const _serverPage = 5;

  /// Shown under the server field when what is typed cannot be used.
  String? _esploraError;

  /// Whether the server field holds something Save would reject. Save falls
  /// back to mempool.space for it, and onboarding ignored that, so a mistyped
  /// node address sent every wallet address to mempool.space without a word
  /// (audit U-3). Checked on leaving the page, and again at Get Started,
  /// since the pages can be swiped past.
  bool _serverOk() {
    final typed = _esploraCtrl.text.trim();
    if (typed.isEmpty || normalizeServerUrl(typed) != null) return true;
    setState(
      () =>
          _esploraError =
              "That isn't a usable server address. Correct it, or clear it "
              'to use mempool.space.',
    );
    if (_page != _serverPage) {
      _controller.animateToPage(
        _serverPage,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
    return false;
  }

  void _next() {
    if (_page == _serverPage && !_serverOk()) return;
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
    if (!_serverOk()) return;
    // Save currency. The price is switched with the label, not after the
    // write, so the two never disagree (audit U-8).
    app.btcPriceService.switchCurrency(_currency);
    app.currencyNotifier.value = _currency;
    await app.db
        .into(app.db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingCurrency,
            value: _currency,
          ),
        );

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
        // Nothing to persist beyond the provider choice itself, which
        // `setActiveProvider` above already wrote.
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
    // Starts from what is in force, not from defaults. Settings → About can
    // send the user back through here, and every field is written back at the
    // end: starting from defaults quietly switched a self-hosted Esplora
    // server back to mempool.space — so the next sync sent the wallet's
    // addresses to a public server — and reset the theme, the currency and
    // the AI server's URL.
    final ai = app.ollamaService;
    _currency = app.currencyNotifier.value;
    _themeMode = app.themeModeNotifier.value;
    final esplora = app.xpubService.esploraBaseUrl;
    _esploraCtrl = TextEditingController(
      text: esplora == AppConstants.mempoolBaseUrl ? '' : esplora,
    );
    _esploraCtrl.addListener(() {
      if (_esploraError != null) setState(() => _esploraError = null);
    });
    _mapleApiKeyCtrl = TextEditingController();
    if (widget.revisit || app.onboardingCompleteNotifier.value) {
      // A revisit: the provider in use is the user's choice, so the
      // availability check must not replace it with a suggestion.
      _aiProvider = ai.activeProvider;
      _aiProviderTouched = true;
    }
    _aiUrlCtrl = TextEditingController(
      text: switch (_aiProvider) {
        AiProvider.ollama => ai.baseUrl,
        AiProvider.lmStudio => ai.lmStudioBaseUrl,
        AiProvider.maple => ai.mapleBaseUrl,
        _ => _aiProvider.defaultUrl ?? '',
      },
    );
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
                  BitcoinServerPage(
                    controller: _esploraCtrl,
                    errorText: _esploraError,
                  ),
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
