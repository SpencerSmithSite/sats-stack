/// Tests for the two stream guards added for the last of the audit's P2 items.
///
/// Both failures they prevent look identical to the user — a spinner that never
/// stops — and neither had anything to end it.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/services/inference/inference_backend.dart';

void main() {
  group('idleTimeout', () {
    test('fails a stream that goes quiet', () async {
      // Short gap so the test is fast; the production values are 45s for a
      // hosted provider and 120s for a local model.
      final controller = StreamController<String>();
      final seen = <String>[];
      Object? error;

      controller.stream
          .idleTimeout(const Duration(milliseconds: 80), 'The model')
          .listen(seen.add, onError: (Object e) => error = e);

      controller.add('first token');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(seen, ['first token']);
      expect(error, isA<InferenceException>());
      expect(error.toString(), contains('stopped responding'));
      await controller.close();
    });

    test('a slow but alive stream is not a broken one', () async {
      // The gap is what matters, not the total: a long answer must not be cut
      // off just for being long.
      final controller = StreamController<String>();
      final seen = <String>[];
      Object? error;

      controller.stream
          .idleTimeout(const Duration(milliseconds: 120), 'The model')
          .listen(seen.add, onError: (Object e) => error = e);

      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        controller.add('token $i');
      }
      await controller.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(error, isNull);
      expect(seen, hasLength(6));
    });
  });

  group('serialisedOnChannel', () {
    test(
      'a second generation waits rather than clobbering the first',
      () async {
        // EventChannel.receiveBroadcastStream installs one handler per channel
        // name, so a concurrent listen replaces the first — which then receives
        // nothing and never completes. Reachable by generating the dashboard
        // insight on Apple Intelligence while asking a chat question.
        final order = <String>[];
        final first = StreamController<String>();

        final a =
            serialisedOnChannel('test/chan', () {
              order.add('first opened');
              return first.stream;
            }).toList();

        // Let the first subscription establish itself.
        await Future<void>.delayed(Duration.zero);

        final b =
            serialisedOnChannel('test/chan', () {
              order.add('second opened');
              return Stream.fromIterable(['b1']);
            }).toList();

        await Future<void>.delayed(const Duration(milliseconds: 20));
        // The second has not touched the channel yet.
        expect(order, ['first opened']);

        first.add('a1');
        await first.close();

        expect(await a, ['a1']);
        expect(await b, ['b1']);
        expect(order, ['first opened', 'second opened']);
      },
    );

    test('a failed generation does not block the next one', () async {
      final failing =
          serialisedOnChannel<String>(
            'test/chan2',
            () => Stream.error(StateError('native side died')),
          ).toList();

      await expectLater(failing, throwsStateError);

      final after =
          await serialisedOnChannel<String>(
            'test/chan2',
            () => Stream.fromIterable(['recovered']),
          ).toList();
      expect(after, ['recovered']);
    });

    test('different channels do not queue behind each other', () async {
      final slow = StreamController<String>();
      final onChannelA =
          serialisedOnChannel('test/a', () => slow.stream).toList();

      await Future<void>.delayed(Duration.zero);

      // A different channel name has its own queue, so this finishes while the
      // first is still open.
      expect(
        await serialisedOnChannel(
          'test/b',
          () => Stream.fromIterable(['independent']),
        ).toList(),
        ['independent'],
      );

      slow.add('done');
      await slow.close();
      expect(await onChannelA, ['done']);
    });
  });
}
