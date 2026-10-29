/// A self-hosted AI server can be set up from nothing.
///
/// Ollama, LM Studio and Maple report "unavailable" until a model is chosen,
/// and every caller listed the models only once the backend was available. A
/// first-time setup could therefore never pass its connection test, never see
/// a model list, and so never get a model to choose.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/inference/cloud_backend.dart';
import 'package:sats_stack/core/services/inference/inference_backend.dart';
import 'package:sats_stack/core/services/inference/remote_backends.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';

class _NoKeyStore extends SecureKeyStore {
  const _NoKeyStore();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  final ollama = MockClient((req) async {
    if (req.url.path == '/api/tags') {
      return http.Response(
        jsonEncode({
          'models': [
            {'name': 'llama3.2:3b'},
            {'name': 'qwen3:8b'},
          ],
        }),
        200,
      );
    }
    return http.Response('', 404);
  });

  test('a reachable Ollama with no model chosen is set up', () async {
    final service = OllamaService(db, keyStore: const _NoKeyStore());
    await service.setActiveProvider(AiProvider.ollama);
    expect(service.selectedModel, isNull);

    final ok = await http.runWithClient(service.isAvailable, () => ollama);

    expect(ok, isTrue);
    expect(service.selectedModel, 'llama3.2:3b');
  });

  test('a chosen model is left alone', () async {
    final service = OllamaService(db, keyStore: const _NoKeyStore());
    await service.setActiveProvider(AiProvider.ollama);
    await service.saveSettings(model: 'qwen3:8b');

    await http.runWithClient(service.isAvailable, () => ollama);

    expect(service.selectedModel, 'qwen3:8b');
  });

  test('an unreachable server is still unavailable', () async {
    final service = OllamaService(db, keyStore: const _NoKeyStore());
    await service.setActiveProvider(AiProvider.ollama);
    final down = MockClient((_) async => throw http.ClientException('down'));

    final ok = await http.runWithClient(service.isAvailable, () => down);

    expect(ok, isFalse);
    expect(service.selectedModel, isNull);
  });

  group('a self-hosted server that fails says why', () {
    MockClient streaming(int status, String body) =>
        MockClient.streaming((req, _) async {
          return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
        });

    final messages = [
      {'role': 'user', 'content': 'hi'},
    ];

    test('in the middle of an answer', () async {
      // The model ran out of memory after one token. The error line was
      // skipped as malformed, so "Hel" was saved as the complete answer.
      final backend = OllamaBackend(
        baseUrl: 'http://localhost:11434',
        model: 'llama3.2:3b',
      );
      final client = streaming(
        200,
        '{"message":{"content":"Hel"}}\n'
        '{"error":"model runner has unexpectedly stopped"}\n',
      );
      await expectLater(
        backend.chat(messages, client: client).toList(),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'message',
            contains('unexpectedly stopped'),
          ),
        ),
      );
    });

    test('before it starts, in the server\'s words', () async {
      final backend = OllamaBackend(
        baseUrl: 'http://localhost:11434',
        model: 'llama3',
      );
      final client = streaming(404, '{"error":"model \'llama3\' not found"}');
      await expectLater(
        backend.chat(messages, client: client).toList(),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'message',
            contains("model 'llama3' not found"),
          ),
        ),
      );
    });

    test('an OpenAI-compatible error frame', () async {
      final backend = OpenAiCompatBackend(
        id: 'lmStudio',
        displayName: 'LM Studio',
        description: '',
        baseUrl: 'http://localhost:1234/v1',
        model: 'm',
        apiKey: '',
        isPrivate: true,
        contextBudgetChars: 4000,
      );
      final client = streaming(
        200,
        'data: {"choices":[{"delta":{"content":"Hi"}}]}\n'
        'data: {"error":{"message":"context length exceeded"}}\n',
      );
      await expectLater(
        backend.chat(messages, client: client).toList(),
        throwsA(isA<InferenceException>()),
      );
    });
  });

  test(
    'a hosted answer keeps its last frame without a final newline',
    () async {
      const backend = CloudBackend(
        provider: CloudProvider.openai,
        model: 'm',
        apiKey: 'k',
      );
      final client = MockClient.streaming(
        (req, _) async => http.StreamedResponse(
          Stream.value(
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"Spend "}}]}\n'
              'data: {"choices":[{"delta":{"content":"less."}}]}',
            ),
          ),
          200,
        ),
      );
      final answer =
          await backend.chat([
            {'role': 'user', 'content': 'hi'},
          ], client: client).join();
      expect(answer, 'Spend less.');
    },
  );

  test('a rejected key is not echoed back from the server', () async {
    final backend = OpenAiCompatBackend(
      id: 'maple',
      displayName: 'Maple',
      description: '',
      baseUrl: 'https://maple.example.com/v1',
      model: 'm',
      apiKey: 'sk-secret-123',
      isPrivate: false,
      contextBudgetChars: 4000,
    );
    final client = MockClient.streaming(
      (req, _) async => http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"bad key sk-secret-123"}')),
        401,
      ),
    );
    await expectLater(
      backend.chat([
        {'role': 'user', 'content': 'hi'},
      ], client: client).toList(),
      throwsA(
        isA<InferenceException>().having(
          (e) => e.message,
          'message',
          isNot(contains('sk-secret')),
        ),
      ),
    );
  });
}
