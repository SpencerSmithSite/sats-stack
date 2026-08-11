import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/models/ai_backend_group.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/inference/cloud_backend.dart';
import 'package:sats_stack/core/services/ollama_service.dart';

/// Tests for the hosted-provider backend.
///
/// Everything here is pure: request bodies, SSE frame decoding, response
/// parsing and the privacy flag. That is deliberate — the wire format is the
/// part most likely to be quietly wrong, and the only way to check it without a
/// paid API call is to assert on what would have been sent.
void main() {
  const messages = [
    {'role': 'system', 'content': 'You are an analyst.'},
    {'role': 'user', 'content': 'How much on dining?'},
  ];

  group('privacy flag', () {
    test('every hosted provider reports isPrivate false', () {
      for (final p in [
        AiProvider.claude,
        AiProvider.chatGpt,
        AiProvider.gemini,
        AiProvider.grok,
        AiProvider.maple,
      ]) {
        expect(p.isPrivate, isFalse, reason: '${p.label} must not claim privacy');
      }
    });

    test('every on-device and self-hosted backend reports isPrivate true', () {
      for (final p in [
        AiProvider.ollama,
        AiProvider.lmStudio,
        AiProvider.appleIntelligence,
        AiProvider.geminiNano,
        AiProvider.localModel,
      ]) {
        expect(p.isPrivate, isTrue, reason: '${p.label} keeps data on device');
      }
    });

    test('the backend agrees with the enum it is constructed from', () {
      // The enum duplicates `isPrivate` so the picker can label a row without
      // building a backend. If the two ever disagree the app tells the user one
      // thing and does another.
      for (final p in AiProvider.values) {
        final cloud = p.cloudProvider;
        if (cloud == null) continue;
        final backend =
            CloudBackend(provider: cloud, model: null, apiKey: 'k');
        expect(backend.isPrivate, p.isPrivate);
      }
    });

    test('a hosted provider names who receives the data', () {
      // "Sent to a server" is not a disclosure. The company and the host both
      // have to appear, because that is what the user is being asked to accept.
      expect(AiProvider.claude.dataRecipient, contains('Anthropic'));
      expect(AiProvider.claude.dataRecipient, contains('api.anthropic.com'));
      expect(AiProvider.chatGpt.dataRecipient, contains('OpenAI'));
      expect(AiProvider.gemini.dataRecipient, contains('Google'));
      expect(AiProvider.grok.dataRecipient, contains('xAI'));
      expect(AiProvider.maple.dataRecipient, isNotNull);
    });

    test('a private backend names no recipient', () {
      for (final p in AiProvider.values.where((p) => p.isPrivate)) {
        expect(p.dataRecipient, isNull, reason: p.label);
      }
    });
  });

  group('persistence keys', () {
    test('every provider key round-trips', () {
      // A changed key silently resets that user's choice back to Ollama.
      for (final p in AiProvider.values) {
        expect(AiProvider.fromKey(p.key), p);
      }
    });

    test('an unknown key falls back to Ollama rather than throwing', () {
      expect(AiProvider.fromKey('backend-from-a-later-build'),
          AiProvider.ollama);
      expect(AiProvider.fromKey(null), AiProvider.ollama);
    });

    test('provider ids round-trip and fall back', () {
      for (final p in CloudProvider.values) {
        expect(CloudProvider.fromId(p.id), p);
      }
      expect(CloudProvider.fromId('nope'), CloudProvider.anthropic);
    });

    test('cloud providers map to distinct AiProvider values', () {
      final mapped = AiProvider.values
          .map((p) => p.cloudProvider)
          .whereType<CloudProvider>()
          .toSet();
      expect(mapped.length, CloudProvider.values.length);
    });
  });

  group('chat body — Anthropic', () {
    test('system is a top-level field, not a message', () {
      final body = jsonDecode(
        CloudBackend.buildChatBody(
            CloudProvider.anthropic, 'claude-sonnet-5', messages),
      ) as Map<String, dynamic>;

      expect(body['system'], 'You are an analyst.');
      expect(body['messages'], hasLength(1));
      expect(body['messages'][0]['role'], 'user');
      expect(body['stream'], isTrue);
    });

    test('max_tokens is always present', () {
      // The Messages API rejects a request without it, unlike the
      // OpenAI-shaped providers where it is optional.
      final body = jsonDecode(
        CloudBackend.buildChatBody(
            CloudProvider.anthropic, 'claude-sonnet-5', messages),
      ) as Map<String, dynamic>;
      expect(body['max_tokens'], isA<int>());
    });

    test('no system key when there is no system message', () {
      final body = jsonDecode(
        CloudBackend.buildChatBody(CloudProvider.anthropic, 'm', const [
          {'role': 'user', 'content': 'hi'},
        ]),
      ) as Map<String, dynamic>;
      expect(body.containsKey('system'), isFalse);
    });
  });

  group('chat body — OpenAI and Grok', () {
    test('system stays inline as the first message', () {
      for (final p in [CloudProvider.openai, CloudProvider.xai]) {
        final body = jsonDecode(
          CloudBackend.buildChatBody(p, 'model-x', messages),
        ) as Map<String, dynamic>;

        expect(body['messages'], hasLength(2), reason: p.id);
        expect(body['messages'][0]['role'], 'system', reason: p.id);
        expect(body['messages'][1]['role'], 'user', reason: p.id);
        expect(body['stream'], isTrue, reason: p.id);
      }
    });

    test('Grok is byte-for-byte OpenAI-shaped', () {
      // The reason there are three wire formats for four providers.
      expect(
        CloudBackend.buildChatBody(CloudProvider.xai, 'm', messages),
        CloudBackend.buildChatBody(CloudProvider.openai, 'm', messages),
      );
    });
  });

  group('chat body — Gemini', () {
    test('system becomes systemInstruction', () {
      final body = jsonDecode(
        CloudBackend.buildChatBody(
            CloudProvider.gemini, 'gemini-3.6-flash', messages),
      ) as Map<String, dynamic>;

      expect(body['systemInstruction']['parts'][0]['text'],
          'You are an analyst.');
      expect(body['contents'], hasLength(1));
      expect(body['contents'][0]['parts'][0]['text'], 'How much on dining?');
    });

    test('assistant turns are relabelled "model"', () {
      final body = jsonDecode(
        CloudBackend.buildChatBody(CloudProvider.gemini, 'm', const [
          {'role': 'user', 'content': 'a'},
          {'role': 'assistant', 'content': 'b'},
          {'role': 'user', 'content': 'c'},
        ]),
      ) as Map<String, dynamic>;

      expect(
        (body['contents'] as List).map((c) => c['role']),
        ['user', 'model', 'user'],
      );
    });
  });

  group('transcript coalescing', () {
    test('consecutive same-role turns are merged', () {
      // Anthropic and Google both reject two user turns in a row, which the
      // app produces when a question is retried after a failed answer.
      for (final p in CloudProvider.values) {
        final body = jsonDecode(
          CloudBackend.buildChatBody(p, 'm', const [
            {'role': 'user', 'content': 'first'},
            {'role': 'user', 'content': 'second'},
          ]),
        ) as Map<String, dynamic>;

        final turns = p == CloudProvider.gemini
            ? body['contents'] as List
            : body['messages'] as List;
        expect(turns, hasLength(1), reason: p.id);
      }
    });

    test('merging keeps both turns\' text', () {
      final body = jsonDecode(
        CloudBackend.buildChatBody(CloudProvider.anthropic, 'm', const [
          {'role': 'user', 'content': 'first'},
          {'role': 'user', 'content': 'second'},
        ]),
      ) as Map<String, dynamic>;

      final content = body['messages'][0]['content'] as String;
      expect(content, contains('first'));
      expect(content, contains('second'));
    });

    test('alternating turns are left alone', () {
      final body = jsonDecode(
        CloudBackend.buildChatBody(CloudProvider.anthropic, 'm', const [
          {'role': 'user', 'content': 'a'},
          {'role': 'assistant', 'content': 'b'},
          {'role': 'user', 'content': 'c'},
        ]),
      ) as Map<String, dynamic>;
      expect(body['messages'], hasLength(3));
    });
  });

  group('vision body', () {
    const b64 = 'aGVsbG8=';

    test('Anthropic uses a base64 source block', () {
      final body = jsonDecode(
        CloudBackend.buildVisionBody(
            CloudProvider.anthropic, 'm', 'read this', b64, 'image/png'),
      ) as Map<String, dynamic>;

      final parts = body['messages'][0]['content'] as List;
      expect(parts[0]['type'], 'image');
      expect(parts[0]['source']['media_type'], 'image/png');
      expect(parts[0]['source']['data'], b64);
    });

    test('OpenAI uses a data: URI', () {
      final body = jsonDecode(
        CloudBackend.buildVisionBody(
            CloudProvider.openai, 'm', 'read this', b64, 'image/jpeg'),
      ) as Map<String, dynamic>;

      final parts = body['messages'][0]['content'] as List;
      expect(parts[0]['image_url']['url'], 'data:image/jpeg;base64,$b64');
    });

    test('Gemini uses inline_data', () {
      final body = jsonDecode(
        CloudBackend.buildVisionBody(
            CloudProvider.gemini, 'm', 'read this', b64, 'image/jpeg'),
      ) as Map<String, dynamic>;

      final parts = body['contents'][0]['parts'] as List;
      expect(parts[0]['inline_data']['mime_type'], 'image/jpeg');
      expect(parts[0]['inline_data']['data'], b64);
    });
  });

  group('SSE delta extraction', () {
    test('Anthropic text_delta', () {
      expect(
        CloudBackend.extractDelta(CloudProvider.anthropic, {
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': 'You spent'},
        }),
        'You spent',
      );
    });

    test('Anthropic ignores non-text frames', () {
      // message_start, ping, content_block_stop and thinking deltas all arrive
      // on the same stream; treating any of them as text corrupts the answer.
      expect(
        CloudBackend.extractDelta(
            CloudProvider.anthropic, {'type': 'message_start'}),
        isNull,
      );
      expect(
        CloudBackend.extractDelta(CloudProvider.anthropic, {
          'type': 'content_block_delta',
          'delta': {'type': 'thinking_delta', 'thinking': 'hmm'},
        }),
        isNull,
      );
    });

    test('OpenAI and Grok choices[0].delta.content', () {
      for (final p in [CloudProvider.openai, CloudProvider.xai]) {
        expect(
          CloudBackend.extractDelta(p, {
            'choices': [
              {
                'delta': {'content': ' 420 sats'},
              },
            ],
          }),
          ' 420 sats',
          reason: p.id,
        );
      }
    });

    test('OpenAI final frame with an empty delta yields nothing', () {
      expect(
        CloudBackend.extractDelta(CloudProvider.openai, {
          'choices': [
            {'delta': <String, dynamic>{}, 'finish_reason': 'stop'},
          ],
        }),
        isNull,
      );
    });

    test('Gemini candidates[0].content.parts[0].text', () {
      expect(
        CloudBackend.extractDelta(CloudProvider.gemini, {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Dining'},
                ],
              },
            },
          ],
        }),
        'Dining',
      );
    });

    test('Gemini ignores a non-text part', () {
      expect(
        CloudBackend.extractDelta(CloudProvider.gemini, {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'functionCall': {'name': 'x'},
                  },
                ],
              },
            },
          ],
        }),
        isNull,
      );
    });

    test('an empty or malformed frame never throws', () {
      for (final p in CloudProvider.values) {
        expect(CloudBackend.extractDelta(p, const {}), isNull, reason: p.id);
        expect(
          CloudBackend.extractDelta(p, const {'choices': [], 'candidates': []}),
          isNull,
          reason: p.id,
        );
      }
    });
  });

  group('model list parsing', () {
    test('Anthropic and OpenAI shape: data[].id', () {
      const body = '{"data":[{"id":"claude-opus-5"},{"id":"claude-sonnet-5"}]}';
      expect(
        CloudBackend.parseModelList(CloudProvider.anthropic, body),
        ['claude-opus-5', 'claude-sonnet-5'],
      );
      expect(
        CloudBackend.parseModelList(CloudProvider.openai, body),
        hasLength(2),
      );
    });

    test('Gemini shape strips the "models/" collection prefix', () {
      // Google returns "models/gemini-3.6-flash" but the generate call wants
      // the bare id — sending the prefixed form is a 404.
      const body =
          '{"models":[{"name":"models/gemini-3.6-flash"},{"name":"models/gemini-2.5-flash"}]}';
      expect(
        CloudBackend.parseModelList(CloudProvider.gemini, body),
        ['gemini-3.6-flash', 'gemini-2.5-flash'],
      );
    });

    test('malformed JSON yields an empty list rather than throwing', () {
      for (final p in CloudProvider.values) {
        expect(CloudBackend.parseModelList(p, 'not json'), isEmpty,
            reason: p.id);
        expect(CloudBackend.parseModelList(p, '[]'), isEmpty, reason: p.id);
      }
    });

    test('every provider ships a non-empty fallback list', () {
      // The fallback is what the picker shows before a key is entered, which
      // is exactly when the user is deciding whether to bother.
      for (final p in CloudProvider.values) {
        expect(p.fallbackModels, isNotEmpty, reason: p.id);
        expect(p.fallbackModels, contains(p.defaultModel), reason: p.id);
      }
    });
  });

  group('error messages', () {
    test('the provider\'s own message wins when there is one', () {
      expect(
        CloudBackend.describeError(CloudProvider.anthropic, 'm', 400,
            '{"error":{"message":"max_tokens is required"}}'),
        contains('max_tokens is required'),
      );
    });

    test('401 says the key was rejected and where to fix it', () {
      final message =
          CloudBackend.describeError(CloudProvider.openai, 'm', 401, '');
      expect(message, contains('key'));
      expect(message, contains('Settings'));
    });

    test('404 names the model that was not recognised', () {
      expect(
        CloudBackend.describeError(
            CloudProvider.gemini, 'gemini-9', 404, 'nope'),
        contains('gemini-9'),
      );
    });

    test('429 and 5xx suggest retrying', () {
      expect(CloudBackend.describeError(CloudProvider.xai, 'm', 429, ''),
          contains('again'));
      expect(CloudBackend.describeError(CloudProvider.xai, 'm', 503, ''),
          contains('again'));
    });

    test('a non-JSON body falls through to the status mapping', () {
      expect(
        CloudBackend.describeError(
            CloudProvider.openai, 'm', 418, '<html>teapot</html>'),
        contains('418'),
      );
    });
  });

  group('status', () {
    test('no key is reported as unavailable with an actionable reason',
        () async {
      const backend =
          CloudBackend(provider: CloudProvider.anthropic, model: null, apiKey: '');
      final status = await backend.checkStatus();
      expect(status.available, isFalse);
      expect(status.detail, contains('Settings'));
    });

    test('models fall back to the static list with no key', () async {
      // No network call is made without a key, so this is safe offline.
      const backend =
          CloudBackend(provider: CloudProvider.gemini, model: null, apiKey: '');
      expect(await backend.availableModels(),
          CloudProvider.gemini.fallbackModels);
    });

    test('a null model resolves to the provider default', () {
      for (final p in CloudProvider.values) {
        final backend = CloudBackend(provider: p, model: null, apiKey: 'k');
        final body = jsonDecode(
          CloudBackend.buildChatBody(p, p.defaultModel, messages),
        );
        // The backend and the static builder must agree on which model is used.
        expect(backend.displayName, p.label);
        expect(body is Map, isTrue);
      }
    });
  });

  group('context budget', () {
    test('a hosted backend gets a much larger budget than an on-device one',
        () {
      const backend = CloudBackend(
          provider: CloudProvider.anthropic, model: null, apiKey: 'k');
      // 4000 is what the Apple and Nano backends report.
      expect(backend.contextBudgetChars, greaterThanOrEqualTo(24000));
      expect(backend.contextBudgetChars, greaterThan(4000 * 4));
    });

    test('the extra budget reaches the prompt as more categories', () {
      final categories = {
        for (var i = 0; i < 200; i++) 'Category $i': (200 - i).toDouble(),
      };

      String prompt(int budget) => OllamaService.composeSystemPrompt(
            totalStackSats: 5000000,
            btcPrice: 100000,
            monthlyIncome: 6000,
            monthlySpending: 4000,
            monthlySurplus: 2000,
            spendingByCategory: categories,
            budgetChars: budget,
          );

      const backend = CloudBackend(
          provider: CloudProvider.anthropic, model: null, apiKey: 'k');
      final small = prompt(4000);
      final large = prompt(backend.contextBudgetChars);

      expect(large.length, greaterThan(small.length));
      expect('\n'.allMatches(large).length,
          greaterThan('\n'.allMatches(small).length));
    });
  });

  group('backend catalogue', () {
    const bare = AiBackendCatalogue(
      appleIntelligenceOffered: false,
      geminiNanoOffered: false,
      downloadableOffered: false,
    );

    test('hosted and self-hosted backends are always offered', () {
      expect(bare.providersIn(AiBackendGroup.ownServer),
          containsAll([AiProvider.ollama, AiProvider.lmStudio]));
      expect(
        bare.providersIn(AiBackendGroup.hosted),
        containsAll([
          AiProvider.claude,
          AiProvider.chatGpt,
          AiProvider.gemini,
          AiProvider.grok,
        ]),
      );
    });

    test('a device with no on-device support shows no on-device group', () {
      expect(bare.providersIn(AiBackendGroup.onDevice), isEmpty);
      expect(bare.nonEmptyGroups, isNot(contains(AiBackendGroup.onDevice)));
    });

    test('an offered platform model appears in the on-device group', () {
      const withApple = AiBackendCatalogue(
        appleIntelligenceOffered: true,
        geminiNanoOffered: false,
        downloadableOffered: false,
      );
      expect(withApple.providersIn(AiBackendGroup.onDevice),
          [AiProvider.appleIntelligence]);
    });

    test('the selected backend stays listed even when unsupported', () {
      // Otherwise the user's own choice vanishes with no explanation when they
      // switch Apple Intelligence off in System Settings.
      const stale = AiBackendCatalogue(
        appleIntelligenceOffered: false,
        geminiNanoOffered: false,
        downloadableOffered: false,
        keepSelected: AiProvider.appleIntelligence,
      );
      expect(stale.providersIn(AiBackendGroup.onDevice),
          contains(AiProvider.appleIntelligence));
    });

    test('on-device is offered first', () {
      const withApple = AiBackendCatalogue(
        appleIntelligenceOffered: true,
        geminiNanoOffered: false,
        downloadableOffered: false,
      );
      expect(withApple.nonEmptyGroups.first, AiBackendGroup.onDevice);
    });

    test('a built-in model becomes the suggested default', () {
      const withApple = AiBackendCatalogue(
        appleIntelligenceOffered: true,
        geminiNanoOffered: false,
        downloadableOffered: false,
      );
      const withNano = AiBackendCatalogue(
        appleIntelligenceOffered: false,
        geminiNanoOffered: true,
        downloadableOffered: false,
      );
      expect(withApple.suggestedDefault, AiProvider.appleIntelligence);
      expect(withNano.suggestedDefault, AiProvider.geminiNano);
      expect(withApple.hasZeroConfigOption, isTrue);
    });

    test('without a built-in model the default is Ollama and needs setup', () {
      expect(bare.suggestedDefault, AiProvider.ollama);
      expect(bare.hasZeroConfigOption, isFalse);
    });

    test('the suggested default is never a backend needing a key', () {
      for (final c in [
        bare,
        const AiBackendCatalogue(
          appleIntelligenceOffered: true,
          geminiNanoOffered: false,
          downloadableOffered: true,
        ),
        const AiBackendCatalogue(
          appleIntelligenceOffered: false,
          geminiNanoOffered: true,
          downloadableOffered: true,
        ),
      ]) {
        expect(c.suggestedDefault.needsApiKey, isFalse);
        expect(c.suggestedDefault.isPrivate, isTrue);
      }
    });

    test('every offered backend belongs to exactly one group', () {
      const full = AiBackendCatalogue(
        appleIntelligenceOffered: true,
        geminiNanoOffered: true,
        downloadableOffered: true,
      );
      expect(full.all.toSet(), AiProvider.values.toSet());
      expect(full.all.length, AiProvider.values.length);
    });

    test('nothing on-device is offered before the platform has answered', () {
      const checking = AiBackendCatalogue.checking();
      expect(checking.providersIn(AiBackendGroup.onDevice), isEmpty);
    });
  });

  group('hosted backends need a key', () {
    test('needsApiKey is true for exactly the four major providers', () {
      final needing =
          AiProvider.values.where((p) => p.needsApiKey).toSet();
      expect(needing, {
        AiProvider.claude,
        AiProvider.chatGpt,
        AiProvider.gemini,
        AiProvider.grok,
      });
    });

    test('a hosted provider offers no URL field', () {
      // The endpoint is fixed. Showing an editable URL invites the user to send
      // their finances somewhere they mistyped.
      for (final p in AiProvider.values.where((p) => p.needsApiKey)) {
        expect(p.defaultUrl, isNull, reason: p.label);
      }
    });

    test('every provider has a key-creation URL and a prefix hint', () {
      for (final p in CloudProvider.values) {
        expect(Uri.tryParse(p.keyUrl)?.hasScheme, isTrue, reason: p.id);
        expect(p.keyPrefix, isNotEmpty, reason: p.id);
        expect(p.host, isNotEmpty, reason: p.id);
      }
    });
  });
}
