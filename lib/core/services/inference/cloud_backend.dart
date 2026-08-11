import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'inference_backend.dart';

/// A hosted model the user holds their own API key for.
///
/// There is no official Dart SDK for any of these, so they speak REST directly.
/// Three wire formats cover four providers: Anthropic's Messages API, Google's
/// `generateContent`, and OpenAI chat-completions — which xAI also implements,
/// so Grok needs no code of its own beyond an endpoint and a model list.
///
/// Every provider here is explicitly **not** private. Sats Stack is chosen for
/// being local-first, and selecting one of these sends the user's complete
/// financial picture to a third party. See [CloudBackend.isPrivate].
enum CloudProvider {
  anthropic(
    id: 'anthropic',
    label: 'Claude',
    company: 'Anthropic',
    chatEndpoint: 'https://api.anthropic.com/v1/messages',
    modelsEndpoint: 'https://api.anthropic.com/v1/models',
    // Sonnet rather than Opus: the questions this app asks are short, the
    // answers are two or three sentences, and the user is paying per token on
    // their own key. Opus is one dropdown away for anyone who wants it.
    defaultModel: 'claude-sonnet-5',
    fallbackModels: [
      'claude-opus-5',
      'claude-sonnet-5',
      'claude-haiku-4-5-20251001',
      'claude-fable-5',
    ],
    keyUrl: 'https://console.anthropic.com/settings/keys',
    keyPrefix: 'sk-ant-',
  ),
  openai(
    id: 'openai',
    label: 'ChatGPT',
    company: 'OpenAI',
    chatEndpoint: 'https://api.openai.com/v1/chat/completions',
    modelsEndpoint: 'https://api.openai.com/v1/models',
    // Terra over Sol for the same reason Sonnet beats Opus here — a fraction of
    // the cost for work that is not frontier-hard.
    defaultModel: 'gpt-5.6-terra',
    fallbackModels: ['gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna'],
    keyUrl: 'https://platform.openai.com/api-keys',
    keyPrefix: 'sk-',
  ),
  gemini(
    id: 'gemini',
    label: 'Gemini',
    company: 'Google',
    // The model goes in the path for Gemini, so this is a prefix rather than a
    // complete URL — see [_chatUri].
    chatEndpoint: 'https://generativelanguage.googleapis.com/v1beta/models',
    modelsEndpoint: 'https://generativelanguage.googleapis.com/v1beta/models',
    defaultModel: 'gemini-3.6-flash',
    fallbackModels: [
      'gemini-3.6-flash',
      'gemini-3.5-flash',
      'gemini-3.5-flash-lite',
      'gemini-2.5-flash',
    ],
    keyUrl: 'https://aistudio.google.com/app/apikey',
    keyPrefix: 'AIza',
  ),
  xai(
    id: 'xai',
    label: 'Grok',
    company: 'xAI',
    chatEndpoint: 'https://api.x.ai/v1/chat/completions',
    modelsEndpoint: 'https://api.x.ai/v1/models',
    defaultModel: 'grok-4.5',
    fallbackModels: ['grok-4.5', 'grok-4.3'],
    keyUrl: 'https://console.x.ai',
    keyPrefix: 'xai-',
  );

  const CloudProvider({
    required this.id,
    required this.label,
    required this.company,
    required this.chatEndpoint,
    required this.modelsEndpoint,
    required this.defaultModel,
    required this.fallbackModels,
    required this.keyUrl,
    required this.keyPrefix,
  });

  /// Stable identifier. Persisted, and used as the keychain entry name — so
  /// changing one orphans that user's saved key.
  final String id;

  /// What the user calls it. The product name, not the company: someone looking
  /// for "Claude" will not scan a list for "Anthropic".
  final String label;

  /// Who receives the data. Named in the privacy disclosure, where the company
  /// is the honest subject of the sentence.
  final String company;

  final String chatEndpoint;
  final String modelsEndpoint;
  final String defaultModel;

  /// Shown when the live model list cannot be fetched — no key yet, or offline.
  /// [availableModels] prefers the real list, because a hardcoded one starts
  /// going stale the day it ships.
  final List<String> fallbackModels;

  /// Where the user goes to create a key. Worth showing next to the field:
  /// "where do I get this?" is the first question every time.
  final String keyUrl;

  /// What a key from this provider starts with, used for a gentle format
  /// warning. Advisory only — never a hard rejection, since prefixes change and
  /// refusing a valid key is far worse than accepting an invalid one.
  final String keyPrefix;

  /// The host that receives the user's financial data, for the disclosure.
  String get host => Uri.parse(chatEndpoint).host;

  static CloudProvider fromId(String? id) => CloudProvider.values.firstWhere(
        (p) => p.id == id,
        orElse: () => CloudProvider.anthropic,
      );
}

/// Streams answers from a hosted model using the user's own API key.
class CloudBackend implements InferenceBackend {
  const CloudBackend({
    required this.provider,
    required this.model,
    required this.apiKey,
  });

  final CloudProvider provider;
  final String? model;
  final String apiKey;

  String get _model =>
      (model == null || model!.isEmpty) ? provider.defaultModel : model!;

  @override
  String get id => provider.id;

  @override
  String get displayName => provider.label;

  @override
  String get description =>
      'Uses your own ${provider.label} API key. Your transactions, balances '
      'and questions are sent to ${provider.host}, where ${provider.company}'
      "'s privacy policy and data-retention terms apply — not this app's.";

  /// Always false, and deliberately not conditional on anything.
  ///
  /// This is the one claim in Sats Stack that must never be wrong. Everything
  /// else the app says about privacy is a default that a hosted backend breaks,
  /// so the picker, the onboarding step and the chat screen all read this flag
  /// to decide whether the local-first promise can stand unqualified.
  @override
  bool get isPrivate => false;

  /// Every model here has a context window of a million tokens or more, so this
  /// is not a real ceiling — it is a generous one that the flexing part of the
  /// prompt (the spending-category list) will not reach on any plausible
  /// ledger. Sized to match Maple rather than to the model, because a budget of
  /// "effectively unlimited" would make the prompt builder's sizing untestable.
  @override
  int get contextBudgetChars => 24000;

  bool get _hasKey => apiKey.trim().isNotEmpty;

  Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    switch (provider) {
      case CloudProvider.anthropic:
        headers['x-api-key'] = apiKey;
        headers['anthropic-version'] = '2023-06-01';
      case CloudProvider.openai:
      case CloudProvider.xai:
        headers['Authorization'] = 'Bearer $apiKey';
      case CloudProvider.gemini:
        // Google accepts the key as a header as well as a query parameter.
        // Preferred here: a key in a URL ends up in logs and crash reports.
        headers['x-goog-api-key'] = apiKey;
    }
    return headers;
  }

  Uri get _chatUri => provider == CloudProvider.gemini
      // Gemini puts the model in the path and needs `alt=sse` to stream rather
      // than return one enormous JSON array at the end.
      ? Uri.parse('${provider.chatEndpoint}/$_model:streamGenerateContent'
          '?alt=sse')
      : Uri.parse(provider.chatEndpoint);

  @override
  Future<BackendStatus> checkStatus() async {
    if (!_hasKey) {
      return BackendStatus.unavailable(
        'No ${provider.label} API key saved. Add one in Settings.',
      );
    }
    try {
      final response = await http
          .get(Uri.parse(provider.modelsEndpoint), headers: _headers)
          .timeout(const Duration(seconds: 8));
      return switch (response.statusCode) {
        200 => BackendStatus.available('$_model via ${provider.host}'),
        401 || 403 => BackendStatus.unavailable(
            '${provider.label} rejected the API key.',
          ),
        429 => BackendStatus.unavailable(
            '${provider.label} rate limit reached. Try again shortly.',
          ),
        final s => BackendStatus.unavailable(
            '${provider.label} returned HTTP $s.',
          ),
      };
    } catch (_) {
      return BackendStatus.unavailable('Could not reach ${provider.host}.');
    }
  }

  /// The provider's live model list, falling back to a static one.
  ///
  /// Fetched rather than hardcoded so a model released after this build still
  /// appears in the picker. The fallback covers the two cases where fetching
  /// cannot work — no key entered yet, and no network — and it is also what
  /// makes the picker useful *before* the user has pasted a key, which is when
  /// they are deciding whether to bother.
  @override
  Future<List<String>> availableModels() async {
    if (!_hasKey) return provider.fallbackModels;
    try {
      final response = await http
          .get(Uri.parse(provider.modelsEndpoint), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return provider.fallbackModels;
      final ids = parseModelList(provider, response.body);
      return ids.isEmpty ? provider.fallbackModels : ids;
    } catch (_) {
      return provider.fallbackModels;
    }
  }

  /// Pull model ids out of a list response.
  ///
  /// Static and public so the three response shapes can be tested without a
  /// network round trip or a real API key.
  static List<String> parseModelList(CloudProvider provider, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return const [];
      switch (provider) {
        case CloudProvider.anthropic:
        case CloudProvider.openai:
        case CloudProvider.xai:
          final data = decoded['data'];
          if (data is! List) return const [];
          return data
              .map((m) => m is Map ? m['id'] as String? : null)
              .whereType<String>()
              .toList();
        case CloudProvider.gemini:
          final models = decoded['models'];
          if (models is! List) return const [];
          return models
              .map((m) => m is Map ? m['name'] as String? : null)
              .whereType<String>()
              // Google returns "models/gemini-3.6-flash"; the generate call
              // wants the bare id, so strip the collection prefix here rather
              // than at every use.
              .map((n) => n.startsWith('models/') ? n.substring(7) : n)
              .toList();
      }
    } on FormatException {
      return const [];
    }
  }

  // ── Request bodies ────────────────────────────────────────────────────────

  /// Build the request body for a chat transcript.
  ///
  /// Static and public for the same reason as [parseModelList]: the wire format
  /// is the part most likely to be silently wrong, and asserting on the encoded
  /// body is the only way to catch that without a paid API call.
  static String buildChatBody(
    CloudProvider provider,
    String model,
    List<Map<String, String>> messages,
  ) {
    final system = messages
        .where((m) => m['role'] == 'system')
        .map((m) => m['content'] ?? '')
        .where((c) => c.isNotEmpty)
        .join('\n\n');
    final turns = _coalesce(
      messages.where((m) => m['role'] != 'system').toList(),
    );

    switch (provider) {
      case CloudProvider.anthropic:
        return jsonEncode({
          'model': model,
          // Required by the Messages API, unlike the OpenAI-shaped providers,
          // which treat it as optional.
          'max_tokens': 4096,
          if (system.isNotEmpty) 'system': system,
          'messages': [
            for (final m in turns)
              {'role': _anthropicRole(m['role']), 'content': m['content'] ?? ''},
          ],
          'stream': true,
        });

      case CloudProvider.openai:
      case CloudProvider.xai:
        return jsonEncode({
          'model': model,
          'messages': [
            if (system.isNotEmpty) {'role': 'system', 'content': system},
            ...turns,
          ],
          'stream': true,
        });

      case CloudProvider.gemini:
        return jsonEncode({
          if (system.isNotEmpty)
            'systemInstruction': {
              'parts': [
                {'text': system},
              ],
            },
          'contents': [
            for (final m in turns)
              {
                'role': _geminiRole(m['role']),
                'parts': [
                  {'text': m['content'] ?? ''},
                ],
              },
          ],
        });
    }
  }

  /// Build the body for a single image-plus-text request.
  static String buildVisionBody(
    CloudProvider provider,
    String model,
    String prompt,
    String base64Image,
    String mimeType,
  ) {
    switch (provider) {
      case CloudProvider.anthropic:
        return jsonEncode({
          'model': model,
          'max_tokens': 4096,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': mimeType,
                    'data': base64Image,
                  },
                },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
          'stream': true,
        });

      case CloudProvider.openai:
      case CloudProvider.xai:
        return jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
                },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
          'stream': true,
        });

      case CloudProvider.gemini:
        return jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {
                  'inline_data': {'mime_type': mimeType, 'data': base64Image},
                },
                {'text': prompt},
              ],
            },
          ],
        });
    }
  }

  static String _anthropicRole(String? role) =>
      role == 'assistant' ? 'assistant' : 'user';

  /// Google names the model's own turns `model`, not `assistant`.
  static String _geminiRole(String? role) =>
      role == 'assistant' ? 'model' : 'user';

  /// Merge adjacent turns with the same role into one.
  ///
  /// Anthropic and Google both reject a transcript with two user turns in a
  /// row, which the app can produce — a retry after a failed answer appends a
  /// second user message with no assistant reply between them. The OpenAI-shaped
  /// providers tolerate it, but there is no reason to send them something
  /// different.
  static List<Map<String, String>> _coalesce(List<Map<String, String>> turns) {
    final out = <Map<String, String>>[];
    for (final turn in turns) {
      final role = turn['role'] == 'assistant' ? 'assistant' : 'user';
      final content = turn['content'] ?? '';
      if (out.isNotEmpty && out.last['role'] == role) {
        out.last['content'] = '${out.last['content']}\n\n$content';
      } else {
        out.add({'role': role, 'content': content});
      }
    }
    return out;
  }

  // ── Streaming ─────────────────────────────────────────────────────────────

  /// Pull the incremental text out of one decoded SSE payload.
  ///
  /// Static and public so each provider's frame shape can be tested directly.
  static String? extractDelta(CloudProvider provider, Map<String, dynamic> data) {
    switch (provider) {
      case CloudProvider.anthropic:
        if (data['type'] != 'content_block_delta') return null;
        final delta = data['delta'];
        if (delta is Map && delta['type'] == 'text_delta') {
          return delta['text'] as String?;
        }
        return null;

      case CloudProvider.openai:
      case CloudProvider.xai:
        final choices = data['choices'];
        if (choices is! List || choices.isEmpty) return null;
        final delta = choices.first['delta'];
        return delta is Map ? delta['content'] as String? : null;

      case CloudProvider.gemini:
        final candidates = data['candidates'];
        if (candidates is! List || candidates.isEmpty) return null;
        final parts = candidates.first['content']?['parts'];
        if (parts is! List || parts.isEmpty) return null;
        // A part can carry a function call or inline data instead of text.
        return parts.first is Map ? parts.first['text'] as String? : null;
    }
  }

  @override
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) =>
      _stream(buildChatBody(provider, _model, messages), client: client);

  /// Stream an answer about an image. Every provider here reads images, which
  /// is the main reason the receipt import is worth pointing at one.
  Stream<String> chatWithImage(
    String prompt,
    String base64Image, {
    String mimeType = 'image/jpeg',
    http.Client? client,
  }) =>
      _stream(
        buildVisionBody(provider, _model, prompt, base64Image, mimeType),
        client: client,
        timeout: const Duration(seconds: 60),
      );

  Stream<String> _stream(
    String body, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  }) async* {
    if (!_hasKey) {
      throw InferenceException(
        'No ${provider.label} API key saved. Add one in Settings.',
      );
    }

    final ownedClient = client == null;
    final c = client ?? http.Client();
    try {
      final request = http.Request('POST', _chatUri)
        ..headers.addAll(_headers)
        ..body = body;

      final response = await c.send(request).timeout(timeout);

      if (response.statusCode != 200) {
        final text = await response.stream.bytesToString();
        throw InferenceException(_describeError(response.statusCode, text));
      }

      // All four stream Server-Sent Events, and chunk boundaries do not respect
      // line boundaries — a frame can arrive split across two chunks — so this
      // buffers until a newline is actually seen rather than using LineSplitter
      // on the chunk stream.
      var buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (true) {
          final newline = buffer.indexOf('\n');
          if (newline < 0) break;
          final line = buffer.substring(0, newline).trim();
          buffer = buffer.substring(newline + 1);

          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload.isEmpty || payload == '[DONE]') continue;

          try {
            final decoded = jsonDecode(payload);
            if (decoded is! Map<String, dynamic>) continue;
            final text = extractDelta(provider, decoded);
            if (text != null && text.isNotEmpty) yield text;
          } on FormatException {
            // Keep-alives and SSE comments are not JSON.
          }
        }
      }
    } finally {
      if (ownedClient) c.close();
    }
  }

  /// Turn a failed response into something the user can act on.
  ///
  /// Static and public so the mapping can be tested; the provider's own message
  /// is preferred when it sends one, because it is almost always more specific
  /// than anything derivable from the status code.
  static String describeError(
    CloudProvider provider,
    String model,
    int status,
    String body,
  ) {
    try {
      final decoded = jsonDecode(body);
      final message = decoded is Map
          ? (decoded['error'] is Map
              ? decoded['error']['message']
              : decoded['message'])
          : null;
      if (message is String && message.isNotEmpty) {
        return '${provider.label}: $message';
      }
    } on FormatException {
      // Not JSON — fall through to the status mapping.
    }

    return switch (status) {
      401 || 403 =>
        '${provider.label} rejected the API key. Check it in Settings.',
      404 => '${provider.label} does not recognise the model "$model".',
      429 => '${provider.label} rate limit reached. Try again shortly.',
      final s when s >= 500 =>
        '${provider.label} is having trouble (HTTP $s). Try again shortly.',
      final s => '${provider.label} request failed (HTTP $s).',
    };
  }

  String _describeError(int status, String body) =>
      describeError(provider, _model, status, body);

  @override
  void dispose() {}
}
