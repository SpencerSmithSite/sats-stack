import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:http/http.dart' as http;

import '../database/database.dart';
import '../models/ai_provider.dart';
import '../../shared/constants/app_constants.dart';

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

  // ── Active provider ───────────────────────────────────────────────────────

  AiProvider _activeProvider = AiProvider.ollama;

  // ── Public getters ────────────────────────────────────────────────────────

  AiProvider get activeProvider => _activeProvider;

  /// Base URL of the Ollama server (used for Ollama-specific settings UI).
  String get baseUrl => _baseUrl;

  String get lmStudioBaseUrl => _lmStudioBaseUrl;
  String get mapleBaseUrl => _mapleBaseUrl;
  String get mapleApiKey => _mapleApiKey;

  /// Model selected for the currently active provider.
  String? get selectedModel => switch (_activeProvider) {
        AiProvider.ollama => _selectedModel,
        AiProvider.lmStudio => _lmStudioSelectedModel,
        AiProvider.maple => _mapleSelectedModel,
      };

  // Per-provider model getters (used by settings screen to show all providers).
  String? get ollamaSelectedModel => _selectedModel;
  String? get lmStudioSelectedModel => _lmStudioSelectedModel;
  String? get mapleSelectedModel => _mapleSelectedModel;

  /// Whether the currently active provider has a verified connection.
  bool get isConnected => switch (_activeProvider) {
        AiProvider.ollama => _isConnected,
        AiProvider.lmStudio => _lmStudioConnected,
        AiProvider.maple => _mapleConnected,
      };

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
    _activeProvider = switch (map[AppConstants.settingAiProvider]) {
      'lmStudio' => AiProvider.lmStudio,
      'maple' => AiProvider.maple,
      _ => AiProvider.ollama,
    };
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
  Future<void> saveModelForActiveProvider(String model) async {
    switch (_activeProvider) {
      case AiProvider.ollama:
        await saveSettings(model: model);
      case AiProvider.lmStudio:
        await saveLmStudioSettings(model: model);
      case AiProvider.maple:
        await saveMapleSettings(model: model);
    }
  }

  /// Persist the active provider selection.
  Future<void> setActiveProvider(AiProvider provider) async {
    _activeProvider = provider;
    final str = switch (provider) {
      AiProvider.ollama => 'ollama',
      AiProvider.lmStudio => 'lmStudio',
      AiProvider.maple => 'maple',
    };
    await _upsertSetting(AppConstants.settingAiProvider, str);
  }

  /// Mark the currently active provider as connected/disconnected.
  Future<void> setConnected(bool value) async {
    switch (_activeProvider) {
      case AiProvider.ollama:
        _isConnected = value;
        await _upsertSetting(AppConstants.settingOllamaConnected, value.toString());
      case AiProvider.lmStudio:
        _lmStudioConnected = value;
        await _upsertSetting(AppConstants.settingLmStudioConnected, value.toString());
      case AiProvider.maple:
        _mapleConnected = value;
        await _upsertSetting(AppConstants.settingMapleConnected, value.toString());
    }
  }

  Future<void> _upsertSetting(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  // ── Connectivity ──────────────────────────────────────────────────────────

  /// Returns true if the currently active provider is reachable.
  Future<bool> isAvailable() async {
    return switch (_activeProvider) {
      AiProvider.ollama => _ollamaIsAvailable(_baseUrl),
      AiProvider.lmStudio => _openAiIsAvailable(_lmStudioBaseUrl, ''),
      AiProvider.maple => _openAiIsAvailable(_mapleBaseUrl, _mapleApiKey),
    };
  }

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
  Future<List<String>> listModels() async {
    return switch (_activeProvider) {
      AiProvider.ollama => _ollamaListModels(_baseUrl),
      AiProvider.lmStudio => _openAiListModels(_lmStudioBaseUrl, ''),
      AiProvider.maple => _openAiListModels(_mapleBaseUrl, _mapleApiKey),
    };
  }

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
  }) async* {
    switch (_activeProvider) {
      case AiProvider.ollama:
        yield* _ollamaChat(messages, client: client);
      case AiProvider.lmStudio:
        yield* _openAiChat(
          messages,
          baseUrl: _lmStudioBaseUrl,
          model: _lmStudioSelectedModel,
          apiKey: '',
          client: client,
        );
      case AiProvider.maple:
        yield* _openAiChat(
          messages,
          baseUrl: _mapleBaseUrl,
          model: _mapleSelectedModel,
          apiKey: _mapleApiKey,
          client: client,
        );
    }
  }

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
