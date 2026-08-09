import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:http/http.dart' as http;

import '../database/database.dart';
import '../models/ai_provider.dart';
import '../../shared/constants/app_constants.dart';
import 'inference/gemini_nano_backend.dart';
import 'inference/inference_backend.dart';
import 'inference/local_model_backend.dart';
import 'inference/platform_llm_backend.dart';
import 'inference/remote_backends.dart';

/// Owns the user's AI configuration and hands out the selected backend.
///
/// Named for Ollama because that was the only option when it was written; it is
/// now a facade over `inference/`, where each backend implements
/// [InferenceBackend]. The class keeps its old surface — [chat], [isAvailable],
/// [listModels] — so the chat and import screens did not have to change, but
/// each of those now delegates to whichever backend is selected rather than
/// switching on a provider enum.
class OllamaService {
  OllamaService(this._db);

  final AppDatabase _db;

  // ── Ollama fields ─────────────────────────────────────────────────────────

  String _baseUrl = AppConstants.defaultOllamaUrl;
  String? _selectedModel;
  bool _isConnected = false;

  // ── LM Studio fields ──────────────────────────────────────────────────────

  String _lmStudioBaseUrl = AppConstants.defaultLmStudioUrl;
  String? _lmStudioSelectedModel;
  bool _lmStudioConnected = false;

  // ── Maple fields ──────────────────────────────────────────────────────────

  String _mapleBaseUrl = AppConstants.defaultMapleUrl;
  String? _mapleSelectedModel;
  String _mapleApiKey = '';
  bool _mapleConnected = false;

  // ── On-device fields ──────────────────────────────────────────────────────

  /// Which model in the downloadable catalogue is selected.
  ///
  /// Seeded with the conservative fallback rather than the recommendation,
  /// because picking the recommendation requires reading device memory and that
  /// is asynchronous. [loadSettings] replaces it with what this machine can
  /// actually hold.
  String _localModelId = LocalModelChoice.fallback().id;

  // ── Active provider ───────────────────────────────────────────────────────

  AiProvider _activeProvider = AiProvider.ollama;

  // ── Public getters ────────────────────────────────────────────────────────

  AiProvider get activeProvider => _activeProvider;

  LocalModelChoice get localModel => LocalModelChoice.byId(_localModelId);

  /// The backend for the current selection, constructed fresh each time so a
  /// configuration edit takes effect without anything having to invalidate a
  /// cached instance.
  InferenceBackend get backend => switch (_activeProvider) {
        AiProvider.ollama =>
          OllamaBackend(baseUrl: _baseUrl, model: _selectedModel),
        AiProvider.lmStudio => OpenAiCompatBackend(
            id: OpenAiCompatBackend.lmStudioId,
            displayName: 'LM Studio',
            description:
                'A model running in LM Studio on this machine. Nothing leaves '
                'your device.',
            baseUrl: _lmStudioBaseUrl,
            model: _lmStudioSelectedModel,
            apiKey: '',
            isPrivate: true,
            contextBudgetChars: 12000,
          ),
        AiProvider.maple => OpenAiCompatBackend(
            id: OpenAiCompatBackend.mapleId,
            displayName: 'Maple',
            description:
                'A hosted model. Your financial figures are sent to the server '
                'to answer each question.',
            baseUrl: _mapleBaseUrl,
            model: _mapleSelectedModel,
            apiKey: _mapleApiKey,
            // Hosted, so the privacy disclosure has to say so — this is the one
            // backend where the app's "nothing leaves your device" claim does
            // not hold, and the picker must not let it stand unqualified.
            isPrivate: false,
            contextBudgetChars: 24000,
          ),
        AiProvider.appleIntelligence => const PlatformLlmBackend(),
        AiProvider.geminiNano => const GeminiNanoBackend(),
        AiProvider.localModel => LocalModelBackend(choice: localModel),
      };

  /// How much financial context the active backend can usefully take.
  ///
  /// Exposed so the system prompt builder can size what it sends. Apple's model
  /// and Gemini Nano take roughly a third of what a hosted model does, and
  /// overfilling them degrades the answer rather than erroring.
  int get contextBudgetChars => backend.contextBudgetChars;

  /// Whether the active backend keeps everything on this device.
  bool get sendsDataOffDevice => !backend.isPrivate;

  /// Base URL of the Ollama server (used for Ollama-specific settings UI).
  String get baseUrl => _baseUrl;

  String get lmStudioBaseUrl => _lmStudioBaseUrl;
  String get mapleBaseUrl => _mapleBaseUrl;
  String get mapleApiKey => _mapleApiKey;

  /// Model selected for the currently active provider.
  ///
  /// Null for Apple Intelligence and Gemini Nano: each ships exactly one model
  /// that the OS owns and does not name, so there is nothing for a model picker
  /// to show. The downloadable backend does have a choice, so it reports one.
  String? get selectedModel => switch (_activeProvider) {
        AiProvider.ollama => _selectedModel,
        AiProvider.lmStudio => _lmStudioSelectedModel,
        AiProvider.maple => _mapleSelectedModel,
        AiProvider.localModel => localModel.name,
        AiProvider.appleIntelligence || AiProvider.geminiNano => null,
      };

  // Per-provider model getters (used by settings screen to show all providers).
  String? get ollamaSelectedModel => _selectedModel;
  String? get lmStudioSelectedModel => _lmStudioSelectedModel;
  String? get mapleSelectedModel => _mapleSelectedModel;

  /// Whether the active backend is ready to answer.
  ///
  /// For the server-backed providers this is a persisted flag, set the last
  /// time a connection was verified. For the on-device backends "connected" is
  /// the wrong idea — there is no host — so it reflects the last availability
  /// report from the OS, refreshed by [refreshOnDeviceReadiness]. Defaults to
  /// false until that first check completes, so nothing claims readiness it has
  /// not confirmed.
  bool get isConnected => switch (_activeProvider) {
        AiProvider.ollama => _isConnected,
        AiProvider.lmStudio => _lmStudioConnected,
        AiProvider.maple => _mapleConnected,
        AiProvider.appleIntelligence ||
        AiProvider.geminiNano ||
        AiProvider.localModel =>
          _onDeviceReady,
      };

  bool _onDeviceReady = false;

  /// Re-ask the active on-device backend whether it can answer.
  ///
  /// Separate from [setConnected] because nothing here is persisted: the answer
  /// can change between launches without the app doing anything — the user
  /// turns Apple Intelligence on, AICore finishes a download, someone deletes
  /// the downloaded weights — so it is always read fresh rather than trusted
  /// from disk.
  Future<bool> refreshOnDeviceReadiness() async {
    if (!_activeProvider.isOnDevice) return isConnected;
    _onDeviceReady = (await backend.checkStatus()).available;
    return _onDeviceReady;
  }

  bool get ollamaConnected => _isConnected;
  bool get lmStudioConnected => _lmStudioConnected;
  bool get mapleConnected => _mapleConnected;

  // ── Config (persisted in AppSettings) ────────────────────────────────────

  Future<void> loadSettings() async {
    final rows = await _db.select(_db.appSettings).get();
    final map = {for (final r in rows) r.key: r.value};

    // Ollama
    _baseUrl = map[AppConstants.settingOllamaUrl] ?? AppConstants.defaultOllamaUrl;
    _selectedModel = map[AppConstants.settingOllamaModel];
    _isConnected = map[AppConstants.settingOllamaConnected] == 'true';

    // LM Studio
    _lmStudioBaseUrl =
        map[AppConstants.settingLmStudioUrl] ?? AppConstants.defaultLmStudioUrl;
    _lmStudioSelectedModel = map[AppConstants.settingLmStudioModel];
    _lmStudioConnected = map[AppConstants.settingLmStudioConnected] == 'true';

    // Maple
    _mapleBaseUrl = map[AppConstants.settingMapleUrl] ?? AppConstants.defaultMapleUrl;
    _mapleSelectedModel = map[AppConstants.settingMapleModel];
    _mapleApiKey = map[AppConstants.settingMapleApiKey] ?? '';
    _mapleConnected = map[AppConstants.settingMapleConnected] == 'true';

    // Active provider
    _activeProvider = AiProvider.fromKey(map[AppConstants.settingAiProvider]);

    // Downloadable model. Only when the user has not chosen: an explicit pick
    // is theirs to keep, including a smaller model than the device could
    // manage. Otherwise the recommendation is made from what this machine can
    // actually hold, so a capable Mac is pointed at a capable model without
    // anyone having to discover the picker.
    _localModelId = map[AppConstants.settingLocalModelId] ??
        (await LocalModelChoice.recommendedHere()).id;

    // Availability is never read from disk — see [refreshOnDeviceReadiness].
    if (_activeProvider.isOnDevice) {
      unawaited(refreshOnDeviceReadiness());
    }
  }

  /// Persist the downloadable-model choice.
  Future<void> saveLocalModel(LocalModelChoice choice) async {
    _localModelId = choice.id;
    await _upsertSetting(AppConstants.settingLocalModelId, choice.id);
  }

  /// Persist Ollama settings (URL and/or model).
  Future<void> saveSettings({String? url, String? model}) async {
    if (url != null) {
      _baseUrl = url;
      await _upsertSetting(AppConstants.settingOllamaUrl, url);
    }
    if (model != null) {
      _selectedModel = model;
      await _upsertSetting(AppConstants.settingOllamaModel, model);
    }
  }

  /// Persist LM Studio settings.
  Future<void> saveLmStudioSettings({String? url, String? model}) async {
    if (url != null) {
      _lmStudioBaseUrl = url;
      await _upsertSetting(AppConstants.settingLmStudioUrl, url);
    }
    if (model != null) {
      _lmStudioSelectedModel = model;
      await _upsertSetting(AppConstants.settingLmStudioModel, model);
    }
  }

  /// Persist Maple settings.
  Future<void> saveMapleSettings({String? url, String? model, String? apiKey}) async {
    if (url != null) {
      _mapleBaseUrl = url;
      await _upsertSetting(AppConstants.settingMapleUrl, url);
    }
    if (model != null) {
      _mapleSelectedModel = model;
      await _upsertSetting(AppConstants.settingMapleModel, model);
    }
    if (apiKey != null) {
      _mapleApiKey = apiKey;
      await _upsertSetting(AppConstants.settingMapleApiKey, apiKey);
    }
  }

  /// Save the model for whichever provider is currently active.
  ///
  /// A no-op for the platform backends: neither lets the app choose a model, so
  /// there is nothing to write. Silently ignoring is right here — the callers
  /// are model pickers that are not shown for those backends at all.
  Future<void> saveModelForActiveProvider(String model) async {
    switch (_activeProvider) {
      case AiProvider.ollama:
        await saveSettings(model: model);
      case AiProvider.lmStudio:
        await saveLmStudioSettings(model: model);
      case AiProvider.maple:
        await saveMapleSettings(model: model);
      case AiProvider.localModel:
        await saveLocalModel(
          LocalModelChoice.catalogue.firstWhere(
            (m) => m.name == model,
            orElse: () => localModel,
          ),
        );
      case AiProvider.appleIntelligence:
      case AiProvider.geminiNano:
        break;
    }
  }

  /// Persist the active provider selection.
  Future<void> setActiveProvider(AiProvider provider) async {
    _activeProvider = provider;
    await _upsertSetting(AppConstants.settingAiProvider, provider.key);
    // A newly-selected on-device backend has no persisted readiness to fall
    // back on, and the stale value belongs to the previous backend.
    _onDeviceReady = false;
    if (provider.isOnDevice) await refreshOnDeviceReadiness();
  }

  /// Mark the currently active provider as connected/disconnected.
  Future<void> setConnected(bool value) async {
    switch (_activeProvider) {
      case AiProvider.ollama:
        _isConnected = value;
        await _upsertSetting(
            AppConstants.settingOllamaConnected, value.toString());
      case AiProvider.lmStudio:
        _lmStudioConnected = value;
        await _upsertSetting(
            AppConstants.settingLmStudioConnected, value.toString());
      case AiProvider.maple:
        _mapleConnected = value;
        await _upsertSetting(
            AppConstants.settingMapleConnected, value.toString());
      case AiProvider.appleIntelligence:
      case AiProvider.geminiNano:
      case AiProvider.localModel:
        // Not persisted — the OS owns this answer and it can change between
        // launches without the app doing anything.
        _onDeviceReady = value;
    }
  }

  Future<void> _upsertSetting(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  // ── Connectivity ──────────────────────────────────────────────────────────

  /// Whether the active backend can answer right now.
  ///
  /// Delegates rather than switching: "reachable" means a reachable host for
  /// Ollama, a valid key for a hosted model, and something else entirely for
  /// the on-device backends — supported hardware, a setting switched on, or
  /// weights present. Each backend is the only thing that knows which.
  Future<bool> isAvailable() async => (await backend.checkStatus()).available;

  /// The same check, keeping the reason. Prefer this where the UI has room to
  /// say what is wrong: "Apple Intelligence is switched off. Turn it on in
  /// Settings" is actionable in a way that a greyed-out row is not.
  Future<BackendStatus> checkStatus() => backend.checkStatus();

  Future<bool> _ollamaIsAvailable(String url) async {
    try {
      final response = await http
          .get(Uri.parse('$url/api/tags'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _openAiIsAvailable(String url, String apiKey) async {
    try {
      final headers = <String, String>{};
      if (apiKey.isNotEmpty) headers['Authorization'] = 'Bearer $apiKey';
      final response = await http
          .get(Uri.parse('$url/models'), headers: headers)
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Models ────────────────────────────────────────────────────────────────

  /// Lists available models for the currently active provider.
  ///
  /// Empty for Apple Intelligence and Gemini Nano — each ships one model the OS
  /// owns. Callers should treat an empty list as "no choice to make" rather
  /// than as a failure to fetch.
  Future<List<String>> listModels() => backend.availableModels();

  Future<List<String>> _ollamaListModels(String url) async {
    try {
      final response = await http
          .get(Uri.parse('$url/api/tags'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (data['models'] as List<dynamic>?) ?? [];
      return models.map((m) => m['name'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> _openAiListModels(String url, String apiKey) async {
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (apiKey.isNotEmpty) headers['Authorization'] = 'Bearer $apiKey';
      final response = await http
          .get(Uri.parse('$url/models'), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (data['data'] as List<dynamic>?) ?? [];
      return models.map((m) => m['id'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  // ── System prompt ─────────────────────────────────────────────────────────

  String buildSystemPrompt({
    required int totalStackSats,
    required double btcPrice,
    required double monthlyIncome,
    required double monthlySpending,
    required double monthlySurplus,
    required Map<String, double> spendingByCategory,
    int? stackGoalSats,
  }) {
    final now = DateTime.now();
    final fiatValue = btcPrice > 0 ? (totalStackSats / 1e8 * btcPrice) : 0.0;
    final top3 = (spendingByCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .map((e) => '  - ${e.key}: \$${e.value.toStringAsFixed(0)}')
        .join('\n');
    final goalLine = stackGoalSats != null && stackGoalSats > 0
        ? 'Stack goal: $stackGoalSats sats (${(totalStackSats / stackGoalSats * 100).toStringAsFixed(1)}% reached)\n'
        : '';

    return '''You are a Bitcoin-native personal finance analyst embedded in Sats Stack, a privacy-first budgeting app. You give concise, actionable advice grounded in the user's real financial data. You think in sats. You are bullish on Bitcoin and understand sound money principles.

Current date: ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}
BTC price: \$${btcPrice.toStringAsFixed(0)} USD

USER FINANCIAL SNAPSHOT
Total Bitcoin stack: $totalStackSats sats (≈ \$${fiatValue.toStringAsFixed(0)})
${goalLine}Monthly income:   \$${monthlyIncome.toStringAsFixed(0)}
Monthly spending: \$${monthlySpending.toStringAsFixed(0)}
Monthly surplus:  \$${monthlySurplus.toStringAsFixed(0)}
Top spending categories this month:
$top3

Keep responses focused and practical. When suggesting actions, quantify them in both fiat and sats. Do not repeat the user's data back verbatim — use it to inform your advice.''';
  }

  // ── Streaming chat ────────────────────────────────────────────────────────

  /// Streams response tokens from the currently active provider.
  ///
  /// If [client] is provided it is used for the request but NOT closed —
  /// the caller owns its lifecycle. Omit to get an auto-managed client.
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) =>
      backend.chat(messages, client: client);

  Stream<String> _ollamaChat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) async* {
    final model = _selectedModel;
    if (model == null || model.isEmpty) {
      throw StateError('No Ollama model selected');
    }

    final ownedClient = client == null;
    final c = client ?? http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$_baseUrl/api/chat'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'model': model,
        'messages': messages,
        'stream': true,
      });

      final streamedResponse =
          await c.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw Exception('Ollama returned ${streamedResponse.statusCode}');
      }

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final data = jsonDecode(line) as Map<String, dynamic>;
          if (data['done'] == true) return;
          final token =
              (data['message'] as Map<String, dynamic>?)?['content'] as String? ?? '';
          if (token.isNotEmpty) yield token;
        } catch (_) {
          // Malformed JSON line — skip
        }
      }
    } finally {
      if (ownedClient) c.close();
    }
  }

  /// OpenAI-compatible SSE streaming chat (LM Studio and Maple).
  Stream<String> _openAiChat(
    List<Map<String, String>> messages, {
    required String baseUrl,
    required String? model,
    required String apiKey,
    http.Client? client,
  }) async* {
    if (model == null || model.isEmpty) {
      throw StateError('No model selected');
    }

    final ownedClient = client == null;
    final c = client ?? http.Client();
    try {
      final request =
          http.Request('POST', Uri.parse('$baseUrl/chat/completions'));
      request.headers['Content-Type'] = 'application/json';
      if (apiKey.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $apiKey';
      }
      request.body = jsonEncode({
        'model': model,
        'messages': messages,
        'stream': true,
      });

      final streamedResponse =
          await c.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw Exception('Server returned ${streamedResponse.statusCode}');
      }

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        if (line == 'data: [DONE]') return;
        if (!line.startsWith('data: ')) continue;

        try {
          final jsonStr = line.substring(6); // strip 'data: ' prefix
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final choices = data['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;

          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          final token = delta?['content'] as String? ?? '';
          if (token.isNotEmpty) yield token;
        } catch (_) {
          // Malformed SSE line — skip
        }
      }
    } finally {
      if (ownedClient) c.close();
    }
  }

  // ── Vision chat ───────────────────────────────────────────────────────────

  /// Returns true if [modelName] suggests the model supports vision/image input.
  static bool looksLikeVisionModel(String? modelName) {
    if (modelName == null || modelName.isEmpty) return false;
    final lower = modelName.toLowerCase();
    return lower.contains('vision') ||
        lower.contains('llava') ||
        lower.contains('moondream') ||
        lower.contains('bakllava') ||
        lower.contains('vl');
  }

  /// Streams response tokens from the active provider for a vision (image+text)
  /// request. [base64Image] is raw base64-encoded image data (no data: prefix).
  Stream<String> chatWithImage(
    String prompt,
    String base64Image, {
    String mimeType = 'image/jpeg',
    http.Client? client,
  }) async* {
    switch (_activeProvider) {
      case AiProvider.ollama:
        yield* _ollamaChatWithImage(prompt, base64Image, client: client);
      case AiProvider.lmStudio:
        yield* _openAiChatWithImage(
          prompt, base64Image,
          mimeType: mimeType,
          baseUrl: _lmStudioBaseUrl,
          model: _lmStudioSelectedModel,
          apiKey: '',
          client: client,
        );
      case AiProvider.maple:
        yield* _openAiChatWithImage(
          prompt, base64Image,
          mimeType: mimeType,
          baseUrl: _mapleBaseUrl,
          model: _mapleSelectedModel,
          apiKey: _mapleApiKey,
          client: client,
        );
      case AiProvider.appleIntelligence:
      case AiProvider.geminiNano:
      case AiProvider.localModel:
        // None of the on-device backends takes an image on the path this app
        // uses: Apple's Foundation Models bridge here is text-only, ML Kit's
        // Prompt API exposes multimodal input separately from the text stream,
        // and the Qwen builds in the catalogue are text-only altogether.
        //
        // Thrown rather than silently returning nothing, because the caller is
        // the receipt-photo import — a blank answer there looks like the model
        // failed to read the image rather than like the wrong backend being
        // selected, and the user needs to know which.
        throw InferenceException(
          '${backend.displayName} cannot read images. Switch to Ollama or a '
          'hosted model in Settings to import from a photo.',
        );
    }
  }

  Stream<String> _ollamaChatWithImage(
    String prompt,
    String base64Image, {
    http.Client? client,
  }) async* {
    final model = _selectedModel;
    if (model == null || model.isEmpty) {
      throw StateError('No Ollama model selected');
    }

    final ownedClient = client == null;
    final c = client ?? http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$_baseUrl/api/chat'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': prompt,
            'images': [base64Image],
          }
        ],
        'stream': true,
      });

      final streamedResponse =
          await c.send(request).timeout(const Duration(seconds: 60));
      if (streamedResponse.statusCode != 200) {
        throw Exception('Ollama returned ${streamedResponse.statusCode}');
      }

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final data = jsonDecode(line) as Map<String, dynamic>;
          if (data['done'] == true) return;
          final token =
              (data['message'] as Map<String, dynamic>?)?['content'] as String? ?? '';
          if (token.isNotEmpty) yield token;
        } catch (_) {}
      }
    } finally {
      if (ownedClient) c.close();
    }
  }

  Stream<String> _openAiChatWithImage(
    String prompt,
    String base64Image, {
    String mimeType = 'image/jpeg',
    required String baseUrl,
    required String? model,
    required String apiKey,
    http.Client? client,
  }) async* {
    if (model == null || model.isEmpty) {
      throw StateError('No model selected');
    }

    final ownedClient = client == null;
    final c = client ?? http.Client();
    try {
      final request =
          http.Request('POST', Uri.parse('$baseUrl/chat/completions'));
      request.headers['Content-Type'] = 'application/json';
      if (apiKey.isNotEmpty) request.headers['Authorization'] = 'Bearer $apiKey';
      request.body = jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
              },
              {
                'type': 'text',
                'text': prompt,
              },
            ],
          }
        ],
        'stream': true,
      });

      final streamedResponse =
          await c.send(request).timeout(const Duration(seconds: 60));
      if (streamedResponse.statusCode != 200) {
        throw Exception('Server returned ${streamedResponse.statusCode}');
      }

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        if (line == 'data: [DONE]') return;
        if (!line.startsWith('data: ')) continue;
        try {
          final data = jsonDecode(line.substring(6)) as Map<String, dynamic>;
          final choices = data['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          final token = delta?['content'] as String? ?? '';
          if (token.isNotEmpty) yield token;
        } catch (_) {}
      }
    } finally {
      if (ownedClient) c.close();
    }
  }

  // ── Monthly insight ───────────────────────────────────────────────────────

  Future<String?> loadCachedInsight() async {
    final rows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingMonthlyInsight)))
        .get();
    return rows.isNotEmpty ? rows.first.value : null;
  }

  Future<bool> isInsightStale() async {
    final dateRows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingMonthlyInsightDate)))
        .get();
    if (dateRows.isEmpty) return true;
    final stored = DateTime.tryParse(dateRows.first.value);
    if (stored == null) return true;
    return DateTime.now().difference(stored).inDays >= 30;
  }

  Future<String> generateMonthlyInsight({
    required int totalStackSats,
    required double btcPrice,
    required double monthlyIncome,
    required double monthlySpending,
    required double monthlySurplus,
    required Map<String, double> spendingByCategory,
    int? stackGoalSats,
  }) async {
    final systemPrompt = buildSystemPrompt(
      totalStackSats: totalStackSats,
      btcPrice: btcPrice,
      monthlyIncome: monthlyIncome,
      monthlySpending: monthlySpending,
      monthlySurplus: monthlySurplus,
      spendingByCategory: spendingByCategory,
      stackGoalSats: stackGoalSats,
    );

    const userPrompt =
        'Give me a 2-3 sentence insight about my finances. '
        'Be specific and honest. Call out the single most important pattern '
        'or opportunity you see. Quantify it in both fiat and sats.';

    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ];

    final buffer = StringBuffer();
    await for (final token in chat(messages)) {
      buffer.write(token);
    }
    final insight = buffer.toString().trim();

    await _upsertSetting(AppConstants.settingMonthlyInsight, insight);
    await _upsertSetting(
      AppConstants.settingMonthlyInsightDate,
      DateTime.now().toIso8601String(),
    );

    return insight;
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> saveConversation({
    required String prompt,
    required String response,
  }) async {
    final model = selectedModel ?? 'unknown';
    await _db.into(_db.aiConversations).insert(
          AiConversationsCompanion.insert(
            prompt: prompt,
            response: response,
            model: model,
          ),
        );
  }

  Future<List<AiConversation>> getHistory({int limit = 20}) {
    return (_db.select(_db.aiConversations)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }
}
