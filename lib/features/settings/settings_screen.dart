import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/database/database.dart';
import '../../core/models/ai_backend_group.dart';
import '../../core/models/ai_provider.dart';
import '../../core/services/inference/cloud_backend.dart';
import '../../core/services/inference/gemini_nano_backend.dart';
import '../../core/services/inference/inference_backend.dart';
import '../../core/services/inference/platform_llm_backend.dart';
import '../../main.dart' as app;
import '../../shared/constants/app_constants.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/platform_utils.dart';
import '../../shared/widgets/ai_privacy_disclosure.dart';
import 'widgets/categories_sheet.dart';
import 'widgets/on_device_ai_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ThemeMode _themeMode = ThemeMode.dark;
  String _currency = 'USD';
  bool _showBtcPrice = true;
  String _appVersion = '';
  String? _inflationRateError;
  late TextEditingController _inflationRateCtrl;

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

  // Bitcoin servers
  late TextEditingController _esploraUrlCtrl;
  bool _testingEsplora = false;
  String? _esploraStatus;

  @override
  void initState() {
    super.initState();
    _themeMode = app.themeModeNotifier.value;
    _currency = app.currencyNotifier.value;
    _showBtcPrice = app.showBtcPriceNotifier.value;
    _inflationRateCtrl = TextEditingController(
        text: app.inflationRateNotifier.value.toString());

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
    _lmStudioUrlCtrl =
        TextEditingController(text: app.ollamaService.lmStudioBaseUrl);
    _lmStudioSelectedModel = app.ollamaService.lmStudioSelectedModel;

    // Maple
    _mapleUrlCtrl = TextEditingController(text: app.ollamaService.mapleBaseUrl);
    _mapleApiKeyCtrl =
        TextEditingController(text: app.ollamaService.mapleApiKey);
    _mapleSelectedModel = app.ollamaService.mapleSelectedModel;

    // Hosted providers. The key field is seeded from the keychain so an already
    // configured provider does not look empty, and the model list starts as the
    // static fallback so the dropdown is useful before any key is entered.
    for (final p in CloudProvider.values) {
      _cloudKeyCtrls[p.id] =
          TextEditingController(text: app.ollamaService.cloudApiKey(p));
      _cloudModels[p.id] = p.fallbackModels;
      _cloudSelectedModel[p.id] = app.ollamaService.cloudModel(p);
      _cloudKeyVisible[p.id] = false;
    }

    // Use empty string when the default server is active so the field shows
    // the placeholder hint instead of the literal mempool.space URL.
    final storedUrl = app.xpubService.esploraBaseUrl;
    _esploraUrlCtrl = TextEditingController(
      text: storedUrl == AppConstants.mempoolBaseUrl ? '' : storedUrl,
    );
    _loadModels();
    _loadVersion();
  }

  @override
  void dispose() {
    _inflationRateCtrl.dispose();
    _ollamaUrlCtrl.dispose();
    _lmStudioUrlCtrl.dispose();
    _mapleUrlCtrl.dispose();
    _mapleApiKeyCtrl.dispose();
    for (final c in _cloudKeyCtrls.values) {
      c.dispose();
    }
    _esploraUrlCtrl.dispose();
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
      case AiProvider.localModel:
        // No model list to fetch: Apple and Google each ship one model the OS
        // owns, and the downloadable catalogue is a fixed list rendered by
        // `_LocalModelSection` rather than something queried from a server.
        // Ask instead whether the backend can answer, which is the equivalent
        // question for these.
        await app.ollamaService.refreshOnDeviceReadiness();
        if (mounted) setState(() {});
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = 'v${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      // Plugin not available in this build configuration — version stays hidden.
    }
  }

  Future<void> _saveInflationRate() async {
    final raw = double.tryParse(_inflationRateCtrl.text.trim());
    if (raw == null || raw < 0 || raw > 100) {
      setState(() =>
          _inflationRateError = 'Please enter a value between 0 and 100');
      return;
    }
    setState(() => _inflationRateError = null);
    app.inflationRateNotifier.value = raw;
    await app.db.into(app.db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingInflationRate,
            value: raw.toString(),
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Inflation rate saved')));
    }
  }

  Future<void> _saveTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    app.themeModeNotifier.value = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await app.db.into(app.db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingThemeMode,
            value: value,
          ),
        );
  }

  Future<void> _saveCurrency(String code) async {
    setState(() => _currency = code);
    app.currencyNotifier.value = code;
    await app.db.into(app.db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingCurrency,
            value: code,
          ),
        );
    // Switch currency in price service — uses cached in-memory prices when
    // available so no extra network request is needed.
    app.btcPriceService.switchCurrency(code);
  }

  Future<void> _saveShowBtcPrice(bool value) async {
    setState(() => _showBtcPrice = value);
    app.showBtcPriceNotifier.value = value;
    await app.db.into(app.db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingShowBtcPrice,
            value: value.toString(),
          ),
        );
  }

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
    app.aiEnabledNotifier.value = PlatformUtils.isDesktop ||
        provider.isOnDevice ||
        app.ollamaService.isConnected;
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

  // ── Ollama ──────────────────────────────────────────────────────────────

  Future<void> _saveOllama() async {
    final url = _ollamaUrlCtrl.text.trim();
    await app.ollamaService.saveSettings(url: url, model: _selectedModel);
    if (url.isEmpty) {
      await app.ollamaService.setConnected(false);
      app.aiEnabledNotifier.value = PlatformUtils.isDesktop;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ollama settings saved')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _connectionStatus = null;
    });
    await app.ollamaService.saveSettings(url: _ollamaUrlCtrl.text.trim());
    final ok = await app.ollamaService.isAvailable();
    if (!mounted) return;
    if (ok) {
      final models = await app.ollamaService.listModels();
      await app.ollamaService.setConnected(true);
      app.aiEnabledNotifier.value = true;
      if (mounted) {
        setState(() {
          _models = models;
          _testingConnection = false;
          _connectionStatus = 'Connected — ${models.length} model(s) found';
        });
      }
    } else {
      await app.ollamaService.setConnected(false);
      app.aiEnabledNotifier.value = PlatformUtils.isDesktop;
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
    await app.ollamaService
        .saveLmStudioSettings(url: url, model: _lmStudioSelectedModel);
    if (url.isEmpty) {
      await app.ollamaService.setConnected(false);
      app.aiEnabledNotifier.value = PlatformUtils.isDesktop;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LM Studio settings saved')),
      );
    }
  }

  Future<void> _testLmStudioConnection() async {
    setState(() {
      _testingLmStudio = true;
      _lmStudioStatus = null;
    });
    final url = _lmStudioUrlCtrl.text.trim();
    await app.ollamaService.saveLmStudioSettings(url: url);
    final ok = await app.ollamaService.isAvailable();
    if (!mounted) return;
    if (ok) {
      final models = await app.ollamaService.listModels();
      await app.ollamaService.setConnected(true);
      app.aiEnabledNotifier.value = true;
      if (mounted) {
        setState(() {
          _lmStudioModels = models;
          _testingLmStudio = false;
          _lmStudioStatus = 'Connected — ${models.length} model(s) found';
        });
      }
    } else {
      await app.ollamaService.setConnected(false);
      app.aiEnabledNotifier.value = PlatformUtils.isDesktop;
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
      app.aiEnabledNotifier.value = true;
      if (!mounted) return;
      setState(() {
        _cloudModels[p.id] = models;
        _testingCloudId = null;
        _cloudStatus = 'Connected — ${models.length} model(s) available';
      });
    } else {
      await app.ollamaService.setConnected(false);
      app.aiEnabledNotifier.value = PlatformUtils.isDesktop;
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
    await app.ollamaService
        .saveMapleSettings(url: url, model: _mapleSelectedModel, apiKey: key);
    if (url.isEmpty) {
      await app.ollamaService.setConnected(false);
      app.aiEnabledNotifier.value = PlatformUtils.isDesktop;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maple settings saved')),
      );
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
    final ok = await app.ollamaService.isAvailable();
    if (!mounted) return;
    if (ok) {
      final models = await app.ollamaService.listModels();
      await app.ollamaService.setConnected(true);
      app.aiEnabledNotifier.value = true;
      if (mounted) {
        setState(() {
          _mapleModels = models;
          _testingMaple = false;
          _mapleStatus = 'Connected — ${models.length} model(s) found';
        });
      }
    } else {
      await app.ollamaService.setConnected(false);
      app.aiEnabledNotifier.value = PlatformUtils.isDesktop;
      setState(() {
        _testingMaple = false;
        _mapleStatus = 'Could not reach Maple at $url';
      });
    }
  }

  Future<void> _exportDb() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final dbFile = File('${dir.path}/sats_stack_db.sqlite');
      if (!dbFile.existsSync()) {
        _showSnack('Database file not found');
        return;
      }
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Sats Stack database',
        fileName: 'sats_stack_backup.sqlite',
        allowedExtensions: ['sqlite', 'db'],
        type: FileType.custom,
      );
      if (savePath == null) return;
      await dbFile.copy(savePath);
      _showSnack('Database exported successfully');
    } catch (e) {
      _showSnack('Export failed: $e');
    }
  }

  Future<void> _importDb() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import database?'),
        content: const Text(
          'This will replace all current data with the selected backup. The app will need to restart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger),
            child: const Text('Replace & Restart'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Sats Stack backup',
        allowedExtensions: ['sqlite', 'db'],
        type: FileType.custom,
      );
      if (result == null || result.files.single.path == null) return;

      final srcFile = File(result.files.single.path!);
      final dir = await getApplicationSupportDirectory();
      final destPath = '${dir.path}/sats_stack_db.sqlite';

      await app.db.close();
      await srcFile.copy(destPath);

      // Restart prompt — hot reload / full restart needed to reopen DB
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Import complete'),
            content: const Text(
              'The database has been replaced. Please restart the app to load the imported data.',
            ),
            actions: [
              FilledButton(
                onPressed: () => exit(0),
                child: const Text('Quit & Restart'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showSnack('Import failed: $e');
    }
  }

  Future<void> _saveBitcoinServers() async {
    await app.xpubService.saveSettings(url: _esploraUrlCtrl.text);
    await app.btcPriceService.loadSettings(); // reload from the same key
    if (mounted) setState(() {}); // refresh privacy warning
    _showSnack('Bitcoin server settings saved');
  }

  Future<void> _testEsploraConnection() async {
    setState(() {
      _testingEsplora = true;
      _esploraStatus = null;
    });

    // Normalise the URL: trim trailing slashes, fall back to mempool.space.
    final raw = _esploraUrlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final base = raw.isNotEmpty ? raw : 'https://mempool.space/api';

    try {
      // ── 1. Block height — standard Esplora endpoint ──────────────────────
      final heightResp = await http
          .get(Uri.parse('$base/blocks/tip/height'))
          .timeout(const Duration(seconds: 8));

      if (heightResp.statusCode != 200) {
        setState(() {
          _esploraStatus = 'HTTP ${heightResp.statusCode} — '
              'is this a valid Esplora / Mempool URL?';
          _testingEsplora = false;
        });
        return;
      }

      final blockHeight = int.tryParse(heightResp.body.trim()) ?? 0;
      final heightStr = blockHeight > 0
          ? 'Block height: ${_fmtInt(blockHeight)}'
          : 'Connected';

      // ── 2. Price endpoint — Mempool-specific, optional ───────────────────
      String priceStr = '';
      try {
        final priceResp = await http
            .get(Uri.parse('$base/v1/prices'))
            .timeout(const Duration(seconds: 5));
        if (priceResp.statusCode == 200) {
          final json =
              jsonDecode(priceResp.body) as Map<String, dynamic>;
          final currency = app.currencyNotifier.value;
          final price = json[currency.toUpperCase()];
          if (price != null) {
            priceStr =
                ' · BTC price: ${CurrencyUtils.format((price as num).toDouble(), currency, decimalDigits: 0)}';
          } else {
            priceStr = ' · Price data available';
          }
        }
      } catch (_) {
        // Price endpoint absent — fine, not all Esplora nodes have it
      }

      if (mounted) {
        setState(() {
          _esploraStatus = '$heightStr$priceStr';
          _testingEsplora = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _esploraStatus =
              'Could not reach server — ${e.toString().replaceAll('Exception: ', '')}';
          _testingEsplora = false;
        });
      }
    }
  }

  String _fmtInt(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  bool get _usingDefaultServer {
    final text = _esploraUrlCtrl.text.trim();
    return text.isEmpty || text.contains('mempool.space');
  }

  Future<void> _resetAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all data?'),
        content: const Text(
          'This will permanently delete all transactions, wallets, budgets, AI conversations, settings, and any saved AI API keys.\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await app.db.resetAndReseed();
    // API keys live in the keychain, so `resetAndReseed` cannot reach them.
    // Leaving a user's credentials behind after "delete everything" would be a
    // genuine surprise — and on a shared or resold device, a real leak.
    await app.ollamaService.clearAllApiKeys();
    app.themeModeNotifier.value = ThemeMode.dark;

    if (mounted) context.go('/onboarding');
  }

  Future<void> _resetOnboarding() async {
    await (app.db.delete(app.db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingOnboardingComplete)))
        .go();
    if (mounted) context.go('/onboarding');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── General ───────────────────────────────────────────────────
          ExpansionTile(
            leading: const Icon(Icons.tune_outlined),
            title: const Text('General'),
            childrenPadding: EdgeInsets.zero,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              _SettingsTile(
                title: 'Theme',
                subtitle: _themeName(_themeMode),
                trailing: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined, size: 18),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined, size: 18),
                      label: Text('Dark'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined, size: 18),
                      label: Text('System'),
                    ),
                  ],
                  selected: {_themeMode},
                  onSelectionChanged: (s) => _saveTheme(s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              _SettingsTile(
                title: 'Currency',
                subtitle: '${CurrencyUtils.symbolFor(_currency)} $_currency',
                trailing: Wrap(
                  spacing: 6,
                  children: CurrencyUtils.supported
                      .map(
                        (code) => ChoiceChip(
                          label: Text(code),
                          selected: _currency == code,
                          onSelected: (_) => _saveCurrency(code),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.currency_bitcoin),
                title: const Text('Show BTC price'),
                subtitle: const Text(
                    'Displays live price in the app bar. '
                    'When off, no price requests are made to any server.'),
                value: _showBtcPrice,
                onChanged: _saveShowBtcPrice,
              ),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('Categories'),
                subtitle:
                    const Text('Add, edit, or remove spending categories'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) =>
                      CategoriesSheet(categoryService: app.categoryService),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader('Expected Inflation Rate'),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inflationRateCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              suffixText: '%',
                              errorText: _inflationRateError,
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) {
                              if (_inflationRateError != null) {
                                setState(() => _inflationRateError = null);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _saveInflationRate,
                          style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Used to calculate the real purchasing power loss of '
                      'your fiat holdings over time.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Servers ───────────────────────────────────────────────────
          ExpansionTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Servers'),
            childrenPadding: EdgeInsets.zero,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              ...[
                const _SectionHeader('AI Provider'),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                              color: AppColors.textSecondary,
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
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                      // The one claim in this app that must never be wrong. A
                      // hosted backend sends the user's complete financial
                      // picture to a third party, and that cannot sit under a
                      // blanket "local-first" promise unqualified.
                      if (!_selectedProvider.isPrivate) ...[
                        const SizedBox(height: 8),
                        AiPrivacyDisclosure(provider: _selectedProvider),
                      ],
                      const SizedBox(height: 14),

                      // ── Ollama fields ───────────────────────────────
                      if (_selectedProvider == AiProvider.ollama) ...[
                        TextField(
                          controller: _ollamaUrlCtrl,
                          decoration: InputDecoration(
                            labelText: 'Ollama base URL',
                            hintText: PlatformUtils.isDesktop
                                ? 'http://localhost:11434'
                                : 'http://your-server:11434',
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_models.isNotEmpty)
                          DropdownButtonFormField<String>(
                            value: _models.contains(_selectedModel)
                                ? _selectedModel
                                : null,
                            decoration:
                                const InputDecoration(labelText: 'Model'),
                            hint: const Text('Select model'),
                            items: _models
                                .map((m) => DropdownMenuItem(
                                    value: m, child: Text(m)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedModel = v),
                          )
                        else
                          Text(
                            'No models loaded — test the connection first.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        const SizedBox(height: 12),
                        if (_connectionStatus != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _connectionStatus!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _connectionStatus!
                                        .startsWith('Connected')
                                    ? AppColors.success
                                    : AppColors.danger,
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _testingConnection
                                  ? null
                                  : _testConnection,
                              icon: _testingConnection
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(
                                      Icons.wifi_tethering_outlined,
                                      size: 18),
                              label: const Text('Test connection'),
                            ),
                            const SizedBox(width: 8),
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
                            value: _lmStudioModels
                                    .contains(_lmStudioSelectedModel)
                                ? _lmStudioSelectedModel
                                : null,
                            decoration:
                                const InputDecoration(labelText: 'Model'),
                            hint: const Text('Select model'),
                            items: _lmStudioModels
                                .map((m) => DropdownMenuItem(
                                    value: m, child: Text(m)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _lmStudioSelectedModel = v),
                          )
                        else
                          Text(
                            'No models loaded — test the connection first.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
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
                                        ? AppColors.success
                                        : AppColors.danger,
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _testingLmStudio
                                  ? null
                                  : _testLmStudioConnection,
                              icon: _testingLmStudio
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(
                                      Icons.wifi_tethering_outlined,
                                      size: 18),
                              label: const Text('Test connection'),
                            ),
                            const SizedBox(width: 8),
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
                            value:
                                _mapleModels.contains(_mapleSelectedModel)
                                    ? _mapleSelectedModel
                                    : null,
                            decoration:
                                const InputDecoration(labelText: 'Model'),
                            hint: const Text('Select model'),
                            items: _mapleModels
                                .map((m) => DropdownMenuItem(
                                    value: m, child: Text(m)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _mapleSelectedModel = v),
                          )
                        else
                          Text(
                            'No models loaded — test the connection first.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        const SizedBox(height: 12),
                        if (_mapleStatus != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _mapleStatus!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _mapleStatus!.startsWith('Connected')
                                    ? AppColors.success
                                    : AppColors.danger,
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _testingMaple
                                  ? null
                                  : _testMapleConnection,
                              icon: _testingMaple
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(
                                      Icons.wifi_tethering_outlined,
                                      size: 18),
                              label: const Text('Test connection'),
                            ),
                            const SizedBox(width: 8),
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
                    detail: _onDeviceStatus?.detail ??
                        'Checking with the system…',
                    isReady: _onDeviceStatus?.available ?? false,
                    onRecheck: _refreshOnDeviceStatus,
                  ),
                // Offered whenever Nano is supported but not yet fetched —
                // this is the only place the download can be started from.
                if (_selectedProvider == AiProvider.geminiNano &&
                    !(_onDeviceStatus?.available ?? true))
                  GeminiNanoDownloadSection(
                    onFinished: _refreshOnDeviceStatus,
                  ),
                if (_selectedProvider == AiProvider.localModel)
                  LocalModelSection(onChanged: _refreshOnDeviceStatus),

                const Divider(indent: 16, endIndent: 16),
              ],
              _SectionHeader('Bitcoin'),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _esploraUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mempool / Esplora server',
                        hintText: 'http://server:3006/api',
                        helperText: 'Used for wallet sync and BTC price. '
                            'Leave blank to use mempool.space.',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _DataRoutingBanner(usingDefault: _usingDefaultServer),
                    const SizedBox(height: 12),
                    if (_esploraStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _esploraStatus!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                _esploraStatus!.startsWith('Could not') ||
                                        _esploraStatus!.startsWith('HTTP')
                                    ? AppColors.danger
                                    : AppColors.success,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _testingEsplora
                              ? null
                              : _testEsploraConnection,
                          icon: _testingEsplora
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_tethering_outlined,
                                  size: 18),
                          label: const Text('Test connection'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _saveBitcoinServers,
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Data ──────────────────────────────────────────────────────
          ExpansionTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Data'),
            childrenPadding: EdgeInsets.zero,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              ListTile(
                leading: const Icon(Icons.upload_outlined),
                title: const Text('Export database'),
                subtitle: const Text('Save a copy of your SQLite file'),
                onTap: _exportDb,
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Import database'),
                subtitle: const Text('Replace current data from a backup'),
                onTap: _importDb,
              ),
            ],
          ),

          // ── About ─────────────────────────────────────────────────────
          ExpansionTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            childrenPadding: EdgeInsets.zero,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Sats Stack'),
                subtitle: Text(
                  'Local-first Bitcoin budgeting. No cloud. No accounts.'
                  '${_appVersion.isNotEmpty ? '\n$_appVersion' : ''}',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.replay_outlined),
                title: const Text('Show onboarding'),
                subtitle: const Text('Revisit the welcome screens'),
                onTap: _resetOnboarding,
              ),
            ],
          ),

          // ── Danger zone ───────────────────────────────────────────────
          ExpansionTile(
            leading: const Icon(Icons.warning_amber_outlined,
                color: AppColors.danger),
            title: const Text(
              'Danger Zone',
              style: TextStyle(color: AppColors.danger),
            ),
            childrenPadding: EdgeInsets.zero,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined,
                    color: AppColors.danger),
                title: const Text(
                  'Reset all data',
                  style: TextStyle(color: AppColors.danger),
                ),
                subtitle: const Text(
                    'Permanently delete all transactions, wallets, budgets, and settings'),
                onTap: _resetAllData,
              ),
            ],
          ),
        ],
      ),
    );
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
    final looksWrong = ctrl.text.trim().isNotEmpty &&
        !ctrl.text.trim().startsWith(cloud.keyPrefix);

    return [
      TextField(
        controller: ctrl,
        obscureText: !visible,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: '${cloud.label} API key',
          hintText: '${cloud.keyPrefix}…',
          helperText: looksWrong
              ? '${cloud.label} keys usually start with "${cloud.keyPrefix}".'
              : 'Stored in this device\'s keychain, not in the app database.',
          helperMaxLines: 2,
          suffixIcon: IconButton(
            icon: Icon(
              visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 19,
            ),
            tooltip: visible ? 'Hide key' : 'Show key',
            onPressed: () =>
                setState(() => _cloudKeyVisible[cloud.id] = !visible),
          ),
        ),
      ),
      ApiKeyHelpLink(provider: _selectedProvider),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        // The saved model may not be in the live list — deprecated, or only
        // available on a different tier — so fall back to showing no selection
        // rather than throwing on a value the dropdown has no item for.
        initialValue: models.contains(selected) ? selected : null,
        decoration: const InputDecoration(labelText: 'Model'),
        hint: Text(selected ?? cloud.defaultModel),
        items: models
            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
            .toList(),
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
              color: _cloudStatus!.startsWith('Connected')
                  ? AppColors.success
                  : AppColors.danger,
            ),
          ),
        ),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: testing ? null : () => _testCloudConnection(cloud),
            icon: testing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_outlined, size: 18),
            label: const Text('Test key'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _saveCloud(cloud),
            child: const Text('Save'),
          ),
        ],
      ),
    ];
  }

  AiBackendCatalogue get _catalogue => AiBackendCatalogue(
        appleIntelligenceOffered: _appleLlm?.state.worthOffering ?? false,
        geminiNanoOffered: _nano?.state.worthOffering ?? false,
        downloadableOffered: AiBackendCatalogue.downloadableRunsHere,
        keepSelected: _selectedProvider,
      );

  PlatformLlmAvailability? _appleLlm;
  GeminiNanoAvailability? _nano;

  /// Ask both platform backends once on open, so the picker knows what to show
  /// before the user touches anything.
  Future<void> _loadPlatformAvailability() async {
    final apple = PlatformLlmBackend.bridgedHere
        ? await PlatformLlmBackend.availability()
        : null;
    final nano =
        GeminiNanoBackend.bridgedHere ? await GeminiNanoBackend.availability() : null;
    if (mounted) {
      setState(() {
        _appleLlm = apple;
        _nano = nano;
      });
    }
  }

  String _providerDescription(AiProvider provider) => switch (provider) {
        AiProvider.ollama =>
          'Self-hosted, runs on your own server or home network.',
        AiProvider.lmStudio =>
          'Fully local, runs models directly on this device. No data leaves.',
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
        AiProvider.localModel =>
          'A small open model you download once, then run offline anywhere.',
        AiProvider.claude ||
        AiProvider.chatGpt ||
        AiProvider.gemini ||
        AiProvider.grok =>
          'By far the most capable option, using your own '
              '${provider.cloudProvider!.company} API key. You pay '
              '${provider.cloudProvider!.company} directly for what you use.',
      };

  String _themeName(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Shows a summary of which servers are used for data, based on whether a
/// custom Mempool/Esplora server is configured.
class _DataRoutingBanner extends StatelessWidget {
  const _DataRoutingBanner({required this.usingDefault});

  final bool usingDefault;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (usingDefault) {
      return _Banner(
        icon: Icons.public,
        iconColor: const Color(0xFF6AB0E8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Using public servers',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6AB0E8),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            _RouteRow(
              label: 'Wallet sync',
              value: 'mempool.space',
              color: const Color(0xFF6AB0E8),
            ),
            _RouteRow(
              label: 'BTC price',
              value: 'mempool.space · CoinGecko (fallback)',
              color: const Color(0xFF6AB0E8),
            ),
            _RouteRow(
              label: 'Historical prices',
              value: 'mempool.space · CoinGecko (fallback)',
              color: const Color(0xFF6AB0E8),
            ),
            const SizedBox(height: 4),
            Text(
              'The operators of these services can see which addresses and prices you request. '
              'Set a self-hosted server below to route all data through it instead.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6AB0E8),
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return _Banner(
      icon: Icons.shield_outlined,
      iconColor: const Color(0xFF6AC86A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'All data routed through your server',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6AC86A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          _RouteRow(
            label: 'Wallet sync',
            value: 'Your server only',
            color: const Color(0xFF6AC86A),
          ),
          _RouteRow(
            label: 'BTC price',
            value: 'Your server only',
            color: const Color(0xFF6AC86A),
          ),
          _RouteRow(
            label: 'Historical prices',
            value: 'Your server only (mempool with price data required)',
            color: const Color(0xFF6AC86A),
          ),
          const SizedBox(height: 4),
          Text(
            'mempool.space and CoinGecko are never contacted. '
            'If your server does not support price history, '
            'imported transaction amounts will show as \$0.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6AC86A),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = iconColor.withOpacity(isDark ? 0.12 : 0.08);
    final border = iconColor.withOpacity(isDark ? 0.35 : 0.20);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color.withAlpha(180),
              ),
            ),
          ),
          Flexible(
            child: Text(
              '→  $value',
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          if (subtitle != null)
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          if (trailing != null) ...[
            const SizedBox(height: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}
