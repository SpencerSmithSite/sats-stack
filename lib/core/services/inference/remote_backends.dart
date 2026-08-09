import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'inference_backend.dart';

/// A model served by Ollama, on this machine or another one the user runs.
///
/// [isPrivate] is true: the host is the user's own hardware, whether that is
/// localhost or a box on their LAN. That is a different claim from a hosted
/// service, and the picker says so.
class OllamaBackend implements InferenceBackend {
  OllamaBackend({required this.baseUrl, required this.model});

  static const String backendId = 'ollama';

  final String baseUrl;
  final String? model;

  @override
  String get id => backendId;

  @override
  String get displayName => 'Ollama';

  @override
  String get description =>
      'A model running on your own machine or one on your network. Nothing '
      'leaves hardware you control.';

  @override
  bool get isPrivate => true;

  /// Generous: Ollama hosts are usually desktops running 7B+ models with a
  /// context window far larger than anything on-device.
  @override
  int get contextBudgetChars => 12000;

  @override
  Future<BackendStatus> checkStatus() async {
    if (model == null || model!.isEmpty) {
      return const BackendStatus.unavailable(
        'No model selected. Pick one in Settings.',
      );
    }
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200
          ? BackendStatus.available('$model on $baseUrl')
          : BackendStatus.unavailable('Ollama returned ${response.statusCode}.');
    } catch (_) {
      return BackendStatus.unavailable('Could not reach Ollama at $baseUrl.');
    }
  }

  @override
  Future<List<String>> availableModels() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (data['models'] as List<dynamic>?) ?? [];
      return models.map((m) => m['name'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) async* {
    final m = model;
    if (m == null || m.isEmpty) {
      throw InferenceException('No Ollama model selected.');
    }

    final ownedClient = client == null;
    final c = client ?? http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'model': m,
        'messages': messages,
        'stream': true,
      });

      final streamedResponse =
          await c.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw InferenceException(
          'Ollama returned ${streamedResponse.statusCode}.',
        );
      }

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final data = jsonDecode(line) as Map<String, dynamic>;
          if (data['done'] == true) return;
          final token = (data['message'] as Map<String, dynamic>?)?['content']
                  as String? ??
              '';
          if (token.isNotEmpty) yield token;
        } catch (_) {
          // Malformed JSON line — skip.
        }
      }
    } finally {
      if (ownedClient) c.close();
    }
  }

  @override
  void dispose() {}
}

/// Any endpoint speaking the OpenAI chat-completions API.
///
/// Covers LM Studio (on this machine, no key) and Maple (hosted, key required)
/// with one implementation, because the wire format is identical and the only
/// differences — the default URL, whether a key is sent, and crucially whether
/// data leaves the device — are configuration rather than behaviour.
class OpenAiCompatBackend implements InferenceBackend {
  OpenAiCompatBackend({
    required this.id,
    required this.displayName,
    required this.description,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.isPrivate,
    required this.contextBudgetChars,
  });

  static const String lmStudioId = 'lmStudio';
  static const String mapleId = 'maple';

  @override
  final String id;
  @override
  final String displayName;
  @override
  final String description;
  @override
  final bool isPrivate;
  @override
  final int contextBudgetChars;

  final String baseUrl;
  final String? model;
  final String apiKey;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      };

  @override
  Future<BackendStatus> checkStatus() async {
    if (model == null || model!.isEmpty) {
      return const BackendStatus.unavailable(
        'No model selected. Pick one in Settings.',
      );
    }
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/models'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 401 || response.statusCode == 403) {
        return const BackendStatus.unavailable(
          'The server rejected the API key.',
        );
      }
      return response.statusCode == 200
          ? BackendStatus.available('$model on $baseUrl')
          : BackendStatus.unavailable('Server returned ${response.statusCode}.');
    } catch (_) {
      return BackendStatus.unavailable('Could not reach $baseUrl.');
    }
  }

  @override
  Future<List<String>> availableModels() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/models'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (data['data'] as List<dynamic>?) ?? [];
      return models.map((m) => m['id'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) async* {
    final m = model;
    if (m == null || m.isEmpty) {
      throw InferenceException('No model selected for $displayName.');
    }

    final ownedClient = client == null;
    final c = client ?? http.Client();
    try {
      final request =
          http.Request('POST', Uri.parse('$baseUrl/chat/completions'));
      request.headers.addAll(_headers);
      request.body = jsonEncode({
        'model': m,
        'messages': messages,
        'stream': true,
      });

      final streamedResponse =
          await c.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw InferenceException(
          'Server returned ${streamedResponse.statusCode}.',
        );
      }

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        if (line == 'data: [DONE]') return;
        if (!line.startsWith('data: ')) continue;

        try {
          final data =
              jsonDecode(line.substring(6)) as Map<String, dynamic>;
          final choices = data['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          final token = delta?['content'] as String? ?? '';
          if (token.isNotEmpty) yield token;
        } catch (_) {
          // Malformed SSE frame — skip.
        }
      }
    } finally {
      if (ownedClient) c.close();
    }
  }

  @override
  void dispose() {}
}
