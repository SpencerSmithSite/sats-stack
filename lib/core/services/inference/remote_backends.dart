import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_backend.dart';
import 'inference_backend.dart';

/// A model served by Ollama, on this machine or another one the user runs.
///
/// [isPrivate] is true: the host is the user's own hardware, whether that is
/// localhost or a box on their LAN. That is a different claim from a hosted
/// service, and the picker says so.
/// How long a self-hosted server may go silent mid-answer before the request
/// is abandoned. Generous: a local model on modest hardware can take a while
/// between tokens, and a slow answer is not a broken one.
const _idleGap = Duration(seconds: 120);

class OllamaBackend implements InferenceBackend {
  OllamaBackend({
    required this.baseUrl,
    required this.model,
    this.isPrivate = true,
  });

  static const String backendId = 'ollama';

  final String baseUrl;
  final String? model;

  /// False when [baseUrl] points somewhere off the user's own network.
  ///
  /// Decided by the caller, which is the only place that knows the URL —
  /// see `OllamaService.isLocalEndpoint`. A LAN address is hardware the user
  /// controls; a public host is not, and the app must not claim otherwise,
  /// because this flag now gates automatic insight generation and the AI
  /// statement parser.
  @override
  final bool isPrivate;

  @override
  String get id => backendId;

  @override
  String get displayName => 'Ollama';

  @override
  String get description =>
      isPrivate
          ? 'A model running on your own machine or one on your network. Nothing '
              'leaves hardware you control.'
          : 'A model running on the server you configured. Your financial figures '
              'are sent there to answer each question.';

  /// Generous: Ollama hosts are usually desktops running 7B+ models with a
  /// context window far larger than anything on-device.
  @override
  int get contextBudgetChars => 12000;

  /// The context window asked of the server: [contextBudgetChars] (about
  /// 3,000–4,000 tokens) with room left for an answer.
  static const numCtx = 8192;

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
          : BackendStatus.unavailable(
            'Ollama returned ${response.statusCode}.',
          );
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
      // whereType, not a cast: one entry missing `name` used to throw inside
      // the try and turn the entire list into [], which the picker reports as
      // "no models loaded".
      return models
          .whereType<Map<String, dynamic>>()
          .map((m) => m['name'])
          .whereType<String>()
          // An embedding model pulled for another tool is listed alongside
          // the chat ones, and fails on the first message.
          .where(CloudBackend.isChatModel)
          .toList();
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
        // The server's default window is a few thousand tokens, smaller than
        // [contextBudgetChars] plus an answer, and it truncates the prompt
        // itself — silently — when the two don't fit (audit A-3).
        'options': {'num_ctx': numCtx},
      });

      final streamedResponse = await c
          .send(request)
          .timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw InferenceException(
          await _describeFailure('Ollama', streamedResponse),
        );
      }

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .idleTimeout(_idleGap, displayName)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final data = _jsonObject(line);
        // Malformed line — skip.
        if (data == null) continue;
        // Ollama reports a failure partway through (the model ran out of
        // memory, say) as an `error` line. It was skipped like a malformed
        // one, so the half-answer so far was saved as if it were complete.
        final error = _errorMessage(data);
        if (error != null) throw InferenceException('Ollama: $error');
        if (data['done'] == true) return;
        final message = data['message'];
        final token = message is Map ? message['content'] : null;
        if (token is String && token.isNotEmpty) yield token;
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
          : BackendStatus.unavailable(
            'Server returned ${response.statusCode}.',
          );
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
      return models
          .whereType<Map<String, dynamic>>()
          .map((m) => m['id'])
          .whereType<String>()
          .where(CloudBackend.isChatModel)
          .toList();
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
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/chat/completions'),
      );
      request.headers.addAll(_headers);
      request.body = jsonEncode({
        'model': m,
        'messages': messages,
        'stream': true,
      });

      final streamedResponse = await c
          .send(request)
          .timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw InferenceException(
          await _describeFailure(displayName, streamedResponse),
        );
      }

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .idleTimeout(_idleGap, displayName)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        if (!line.startsWith('data:')) continue;
        // `substring(5).trim()` rather than matching the exact string
        // 'data: [DONE]': the space after the colon is optional in SSE, and a
        // server that omits it (or adds trailing whitespace) used to fall
        // through the terminator check and then through the 'data: ' prefix
        // filter, so the stream just ended with no explicit finish.
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') return;
        if (payload.isEmpty) continue;

        final data = _jsonObject(payload);
        // Malformed SSE frame — skip.
        if (data == null) continue;
        // A failure partway through arrives as an `error` frame, which was
        // skipped like a malformed one.
        final error = _errorMessage(data);
        if (error != null) throw InferenceException('$displayName: $error');
        // Read defensively: `choices[0]` as a string, or a `delta` that is
        // not a map, threw a TypeError out of the stream rather than an
        // InferenceException the chat could explain.
        final choices = data['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final first = choices.first;
        final delta = first is Map ? first['delta'] : null;
        final token = delta is Map ? delta['content'] : null;
        if (token is String && token.isNotEmpty) yield token;
      }
    } finally {
      if (ownedClient) c.close();
    }
  }

  @override
  void dispose() {}
}

/// [text] as a JSON object, or null if it is not one.
Map<String, dynamic>? _jsonObject(String text) {
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// The error a server put in a JSON body: Ollama's `{"error": "…"}`, or the
/// OpenAI shape `{"error": {"message": "…"}}`.
String? _errorMessage(Map<String, dynamic> data) {
  final error = data['error'];
  if (error is String && error.isNotEmpty) return error;
  if (error is Map && error['message'] is String) {
    return error['message'] as String;
  }
  return null;
}

/// What went wrong with a non-200 response, in the server's own words when it
/// gave any. Only the status code used to be reported, so "model 'llama3'
/// not found" — the one thing the user needed to read — came out as "Ollama
/// returned 404."
Future<String> _describeFailure(
  String server,
  http.StreamedResponse response,
) async {
  // Never the body of an auth failure: a server may echo part of the key it
  // rejected, and this message is shown on screen. The hosted backend follows
  // the same rule.
  final status = response.statusCode;
  if (status == 401 || status == 403) {
    return '$server rejected the API key ($status).';
  }
  String? detail;
  try {
    final body = await response.stream
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 5));
    final data = _jsonObject(body);
    detail = data == null ? null : _errorMessage(data);
    if (detail == null && body.trim().isNotEmpty && body.length <= 200) {
      detail = body.trim();
    }
  } catch (_) {
    // The status code alone, then.
  }
  return detail == null
      ? '$server returned ${response.statusCode}.'
      : '$server returned ${response.statusCode}: $detail';
}
