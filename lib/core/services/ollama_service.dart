import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:http/http.dart' as http;

import '../database/database.dart';
import '../../shared/constants/app_constants.dart';

class OllamaService {
  OllamaService(this._db);

  final AppDatabase _db;

  String _baseUrl = AppConstants.defaultOllamaUrl;
  String? _selectedModel;
  bool _isConnected = false;

  String get baseUrl => _baseUrl;
  String? get selectedModel => _selectedModel;
  bool get isConnected => _isConnected;

  // ── Config (persisted in AppSettings) ───────────────────────────────────────

  Future<void> loadSettings() async {
    final rows = await _db.select(_db.appSettings).get();
    final map = {for (final r in rows) r.key: r.value};
    _baseUrl = map[AppConstants.settingOllamaUrl] ?? AppConstants.defaultOllamaUrl;
    _selectedModel = map[AppConstants.settingOllamaModel];
    _isConnected = map[AppConstants.settingOllamaConnected] == 'true';
  }

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

  Future<void> setConnected(bool value) async {
    _isConnected = value;
    await _upsertSetting(AppConstants.settingOllamaConnected, value.toString());
  }

  Future<void> _upsertSetting(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: value),
    );
  }

  // ── Connectivity ─────────────────────────────────────────────────────────────

  Future<bool> isAvailable() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Models ───────────────────────────────────────────────────────────────────

  Future<List<String>> listModels() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/tags'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (data['models'] as List<dynamic>?) ?? [];
      return models.map((m) => m['name'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  // ── System prompt ────────────────────────────────────────────────────────────

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

  // ── Streaming chat ────────────────────────────────────────────────────────────

  /// Streams response tokens. [messages] must include the system prompt as
  /// the first entry with role 'system'.
  Stream<String> chat(List<Map<String, String>> messages) async* {
    final model = _selectedModel;
    if (model == null || model.isEmpty) {
      throw StateError('No model selected');
    }

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$_baseUrl/api/chat'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'model': model,
        'messages': messages,
        'stream': true,
      });

      final streamedResponse =
          await client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw Exception('Ollama returned ${streamedResponse.statusCode}');
      }

      String buffer = '';
      await for (final bytes in streamedResponse.stream) {
        buffer += utf8.decode(bytes);
        final lines = buffer.split('\n');
        buffer = lines.last; // keep incomplete last line
        for (final line in lines.take(lines.length - 1)) {
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
      }
    } finally {
      client.close();
    }
  }

  // ── Monthly insight ───────────────────────────────────────────────────────────

  /// Returns the cached insight text, or null if none has been stored yet.
  Future<String?> loadCachedInsight() async {
    final rows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingMonthlyInsight)))
        .get();
    return rows.isNotEmpty ? rows.first.value : null;
  }

  /// True if no insight exists or the stored one is older than 30 days.
  Future<bool> isInsightStale() async {
    final dateRows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingMonthlyInsightDate)))
        .get();
    if (dateRows.isEmpty) return true;
    final stored = DateTime.tryParse(dateRows.first.value);
    if (stored == null) return true;
    return DateTime.now().difference(stored).inDays >= 30;
  }

  /// Generates a 2-3 sentence monthly insight using the provided financial
  /// context, streams and collects the full response, then persists it.
  /// Returns the generated text. Throws if Ollama is unavailable or no model
  /// is selected.
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

    // Persist
    await _upsertSetting(AppConstants.settingMonthlyInsight, insight);
    await _upsertSetting(
      AppConstants.settingMonthlyInsightDate,
      DateTime.now().toIso8601String(),
    );

    return insight;
  }

  // ── Persistence ───────────────────────────────────────────────────────────────

  Future<void> saveConversation({
    required String prompt,
    required String response,
  }) async {
    final model = _selectedModel ?? 'unknown';
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
