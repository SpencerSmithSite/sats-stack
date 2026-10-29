/// What the chat shows of an answer, and which models it offers.
///
/// Answers were shown as raw Markdown. Gemini's answer was read from its first
/// part only. A refusal or safety stop was saved as a complete answer. xAI's
/// 400 for a bad key came out as "request failed". The model lists offered
/// embedding, speech and image models, and the picker could show a model other
/// than the one answering.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/services/inference/cloud_backend.dart';
import 'package:sats_stack/shared/utils/model_choices.dart';
import 'package:sats_stack/shared/widgets/markdown_text.dart';

void main() {
  group('Markdown', () {
    test('blocks', () {
      final blocks = MarkdownText.parseBlocks(
        '## Spending\n'
        'This month:\n'
        '- **Food**: £120\n'
        '  - groceries\n'
        '2. Transport\n'
        '\n'
        '```\nraw\n```\n'
        '---',
      );
      expect(blocks.map((b) => b.kind), [
        MarkdownBlockKind.heading,
        MarkdownBlockKind.paragraph,
        MarkdownBlockKind.bullet,
        MarkdownBlockKind.bullet,
        MarkdownBlockKind.numbered,
        MarkdownBlockKind.code,
        MarkdownBlockKind.rule,
      ]);
      expect(blocks[0].level, 2);
      expect(blocks[3].level, 1, reason: 'nested two spaces in');
      expect(blocks[4].marker, '2.');
      expect(blocks[5].text, 'raw');
    });

    test('a fence still streaming is code to the end', () {
      final blocks = MarkdownText.parseBlocks('Here:\n```\nline 1\nline 2');
      expect(blocks.last.kind, MarkdownBlockKind.code);
      expect(blocks.last.text, 'line 1\nline 2');
    });

    String plain(List<InlineSpan> spans) =>
        spans.map((s) => (s as TextSpan).text).join();

    test('inline formatting is applied and its markers removed', () {
      const style = TextStyle(fontSize: 14);
      final spans = MarkdownText.inlineSpans(
        '**Total:** £1,240, *up* 4% — see `Budgets` or [the chart](x)',
        style,
      );
      expect(plain(spans), 'Total: £1,240, up 4% — see Budgets or the chart');
      final bold = spans.cast<TextSpan>().firstWhere((s) => s.text == 'Total:');
      expect(bold.style!.fontWeight, FontWeight.w700);
      final italic = spans.cast<TextSpan>().firstWhere((s) => s.text == 'up');
      expect(italic.style!.fontStyle, FontStyle.italic);
    });

    test('an unclosed marker, and underscores in words, stay as typed', () {
      const style = TextStyle();
      expect(plain(MarkdownText.inlineSpans('**half', style)), '**half');
      expect(
        plain(MarkdownText.inlineSpans('snake_case_name', style)),
        'snake_case_name',
      );
      expect(plain(MarkdownText.inlineSpans('2 * 3 * 4', style)), '2 * 3 * 4');
    });

    testWidgets('renders without the asterisks', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MarkdownText('**Food** costs most')),
        ),
      );
      expect(find.textContaining('**'), findsNothing);
      expect(find.textContaining('Food costs most'), findsOneWidget);
    });
  });

  group('stream frames', () {
    test("Gemini's answer is every text part, not its reasoning", () {
      expect(
        CloudBackend.extractDelta(CloudProvider.gemini, {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'thinking…', 'thought': true},
                  {'text': 'You spent '},
                  {'text': '£120.'},
                ],
              },
            },
          ],
        }),
        'You spent £120.',
      );
    });

    test('a refusal or safety stop is recognised for each provider', () {
      expect(
        CloudBackend.indicatesRefusal(CloudProvider.anthropic, {
          'type': 'message_delta',
          'delta': {'stop_reason': 'refusal'},
        }),
        isNotNull,
      );
      expect(
        CloudBackend.indicatesRefusal(CloudProvider.openai, {
          'choices': [
            {
              'delta': {'refusal': "I can't help with that."},
            },
          ],
        }),
        "I can't help with that.",
      );
      expect(
        CloudBackend.indicatesRefusal(CloudProvider.xai, {
          'choices': [
            {'delta': {}, 'finish_reason': 'content_filter'},
          ],
        }),
        isNotNull,
      );
      expect(
        CloudBackend.indicatesRefusal(CloudProvider.gemini, {
          'candidates': [
            {'finishReason': 'SAFETY'},
          ],
        }),
        contains('safety'),
      );
      expect(
        CloudBackend.indicatesRefusal(CloudProvider.gemini, {
          'promptFeedback': {'blockReason': 'SAFETY'},
        }),
        isNotNull,
      );
    });

    test('a normal end is not a refusal', () {
      expect(
        CloudBackend.indicatesRefusal(CloudProvider.anthropic, {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'},
        }),
        isNull,
      );
      expect(
        CloudBackend.indicatesRefusal(CloudProvider.gemini, {
          'candidates': [
            {'finishReason': 'STOP'},
          ],
        }),
        isNull,
      );
    });
  });

  test("xAI's 400 for a bad key says so, without echoing the key", () {
    final message = CloudBackend.describeError(
      CloudProvider.xai,
      'grok-4',
      400,
      '{"code":"Client specified an invalid argument","error":"Incorrect '
          'API key provided: xa***Zq. You can obtain an API key from '
          'https://console.x.ai."}',
    );
    expect(message, 'Grok rejected the API key. Check it in Settings.');
  });

  test('a string error field is shown', () {
    expect(
      CloudBackend.describeError(
        CloudProvider.xai,
        'grok-4',
        400,
        '{"error":"Model not found"}',
      ),
      contains('Model not found'),
    );
  });

  group('model lists', () {
    test('only chat models are offered', () {
      final ids = CloudBackend.parseModelList(
        CloudProvider.openai,
        '{"data":[{"id":"gpt-5"},{"id":"text-embedding-3-large"},'
        '{"id":"tts-1"},{"id":"whisper-1"},{"id":"dall-e-3"},'
        '{"id":"gpt-4o-realtime-preview"},{"id":"omni-moderation-latest"}]}',
      );
      expect(ids, ['gpt-5']);
    });

    test("Gemini's are filtered by what they support", () {
      final ids = CloudBackend.parseModelList(
        CloudProvider.gemini,
        '{"models":['
        '{"name":"models/gemini-3-flash",'
        '"supportedGenerationMethods":["generateContent"]},'
        '{"name":"models/text-embedding-004",'
        '"supportedGenerationMethods":["embedContent"]}]}',
      );
      expect(ids, ['gemini-3-flash']);
    });

    test('the model in use is offered even when the list lacks it', () {
      expect(modelChoices(['a', 'b'], 'old'), ['old', 'a', 'b']);
      expect(modelChoices(['a', 'b'], 'b'), ['a', 'b']);
      expect(modelChoices(['a'], null), ['a']);
    });
  });
}
