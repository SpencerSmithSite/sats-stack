/// Reading a photo goes through the server backends' own streaming code
/// (audit A-12).
///
/// Image chat was a second copy of that code inside `OllamaService`. It threw
/// a plain `Exception` carrying only the status code, and skipped every frame
/// it could not read — `error` frames included — so a model that ran out of
/// memory partway through ended its answer as if it were complete.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/services/inference/inference_backend.dart';
import 'package:sats_stack/core/services/inference/remote_backends.dart';

/// A server that answers every request with [status] and [lines], and keeps
/// the request body it was sent.
({MockClient client, List<Map<String, dynamic>> bodies}) server(
  int status,
  List<String> lines,
) {
  final bodies = <Map<String, dynamic>>[];
  final client = MockClient.streaming((req, body) async {
    bodies.add(jsonDecode(await body.bytesToString()) as Map<String, dynamic>);
    return http.StreamedResponse(
      Stream.value(utf8.encode(lines.map((l) => '$l\n').join())),
      status,
    );
  });
  return (client: client, bodies: bodies);
}

void main() {
  final ollama = OllamaBackend(
    baseUrl: 'http://localhost:11434',
    model: 'llava',
    isPrivate: true,
  );
  OpenAiCompatBackend maple() => OpenAiCompatBackend(
    id: OpenAiCompatBackend.mapleId,
    displayName: 'Maple',
    description: '',
    baseUrl: 'https://maple.example.com/v1',
    model: 'vision-model',
    apiKey: 'sk-secret',
    isPrivate: false,
    contextBudgetChars: 24000,
  );

  group('Ollama', () {
    test('sends the image in the message and streams the answer', () async {
      final s = server(200, [
        '{"message":{"content":"Total "}}',
        '{"message":{"content":"12.50"}}',
        '{"done":true}',
      ]);
      final answer =
          await ollama
              .chatWithImage('Read this receipt', 'QUJD', client: s.client)
              .join();
      expect(answer, 'Total 12.50');
      final message = (s.bodies.single['messages'] as List).single as Map;
      expect(message['content'], 'Read this receipt');
      expect(message['images'], ['QUJD']);
      expect(s.bodies.single['model'], 'llava');
    });

    test('an error partway through fails, not a half-answer', () async {
      final s = server(200, [
        '{"message":{"content":"Total "}}',
        '{"error":"model requires more system memory"}',
      ]);
      await expectLater(
        ollama.chatWithImage('Read this', 'QUJD', client: s.client).toList(),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'message',
            contains('more system memory'),
          ),
        ),
      );
    });

    test('a failed status gives the server\'s reason', () async {
      final s = server(404, ['{"error":"model \'llava\' not found"}']);
      await expectLater(
        ollama.chatWithImage('Read this', 'QUJD', client: s.client).toList(),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'message',
            contains("model 'llava' not found"),
          ),
        ),
      );
    });
  });

  group('OpenAI-compatible', () {
    test('sends the image as a data URL before the prompt', () async {
      final s = server(200, [
        'data: {"choices":[{"delta":{"content":"Coffee"}}]}',
        'data: [DONE]',
      ]);
      final answer =
          await maple()
              .chatWithImage(
                'Read this',
                'QUJD',
                mimeType: 'image/png',
                client: s.client,
              )
              .join();
      expect(answer, 'Coffee');
      final content =
          ((s.bodies.single['messages'] as List).single as Map)['content']
              as List;
      expect(content.first, {
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,QUJD'},
      });
      expect(content.last, {'type': 'text', 'text': 'Read this'});
    });

    test('a rejected key says so, and does not echo it', () async {
      final s = server(401, [
        '{"error":{"message":"Incorrect API key provided: sk-secret"}}',
      ]);
      await expectLater(
        maple().chatWithImage('Read this', 'QUJD', client: s.client).toList(),
        throwsA(
          isA<InferenceException>()
              .having((e) => e.message, 'message', contains('rejected'))
              .having(
                (e) => e.message,
                'message',
                isNot(contains('sk-secret')),
              ),
        ),
      );
    });

    test('an error frame fails the answer', () async {
      final s = server(200, [
        'data: {"choices":[{"delta":{"content":"Cof"}}]}',
        'data: {"error":{"message":"upstream overloaded"}}',
      ]);
      await expectLater(
        maple().chatWithImage('Read this', 'QUJD', client: s.client).toList(),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'message',
            contains('upstream overloaded'),
          ),
        ),
      );
    });
  });
}
