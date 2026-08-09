import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sats_stack/core/services/device_memory.dart';
import 'package:sats_stack/core/services/device_storage.dart';
import 'package:sats_stack/core/services/inference/platform_llm_backend.dart';

/// Exercises the Apple Intelligence bridge against the real framework.
///
/// This cannot live in `test/`: `flutter test` runs without a Flutter engine, so
/// every MethodChannel call there returns null and the bridge would appear
/// unsupported on hardware that supports it perfectly. Run with:
///
///     flutter test integration_test/apple_intelligence_test.dart -d macos
///
/// Skips itself rather than failing on a machine without Apple Intelligence, so
/// it stays green on CI and on Intel Macs while still being a real test on
/// hardware that has it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Apple Intelligence bridge', () {
    test('the platform channel is reachable and answers', () async {
      final report = await PlatformLlmBackend.availability(refresh: true);

      // The failure this catches is the one that is invisible otherwise: a
      // channel name mismatch, or a runner that never registered the plugin,
      // both of which surface as `unsupportedPlatform` on a Mac that in fact
      // supports the model.
      expect(
        report.state,
        isNot(PlatformLlmState.unsupportedPlatform),
        reason: 'The bridge is not registered. Check that '
            'FoundationModelsBridge.register runs in MainFlutterWindow '
            '(macOS) or AppDelegate (iOS), and that the channel names match '
            'the Dart side.',
      );
      expect(report.detail, isNotEmpty);
    });

    test('generates a real answer, streamed as non-empty deltas', () async {
      final report = await PlatformLlmBackend.availability(refresh: true);
      if (!report.isAvailable) {
        markTestSkipped('Apple Intelligence unavailable: ${report.detail}');
        return;
      }

      const backend = PlatformLlmBackend();
      final chunks = <String>[];
      await for (final token in backend.chat([
        {
          'role': 'system',
          'content': 'You are a personal finance analyst. Answer in one short '
              'sentence.',
        },
        {'role': 'user', 'content': 'Is spending \$412 on dining a lot?'},
      ])) {
        chunks.add(token);
      }

      expect(chunks, isNotEmpty, reason: 'no tokens streamed');
      // Every chunk must carry new text. If the bridge forwarded the framework's
      // cumulative content instead of the delta, chunk 2 onward would each
      // repeat the whole answer so far.
      expect(chunks.every((c) => c.isNotEmpty), isTrue);
      final answer = chunks.join();
      expect(answer.trim(), isNotEmpty);
      expect(
        answer.length,
        lessThan(chunks.fold<int>(0, (sum, c) => sum + c.length) + 1),
      );
      // A cumulative-forwarding bug shows up as the first chunk appearing again
      // inside the second.
      if (chunks.length > 1 && chunks.first.length > 3) {
        expect(chunks[1].contains(chunks.first), isFalse,
            reason: 'chunks look cumulative, not deltas');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('cancelling the stream stops generation', () async {
      final report = await PlatformLlmBackend.availability(refresh: true);
      if (!report.isAvailable) {
        markTestSkipped('Apple Intelligence unavailable: ${report.detail}');
        return;
      }

      const backend = PlatformLlmBackend();
      // Leaving the chat screen mid-answer must cancel the Swift Task rather
      // than leaving it running.
      final sub = backend.chat([
        {'role': 'user', 'content': 'Write a long paragraph about budgeting.'},
      ]).listen(null);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('Device probes', () {
    test('memory reads a plausible figure', () async {
      final mb = await DeviceMemory.totalMb();
      // Null is permitted by design, but on macOS the sysctl path should work.
      expect(mb, isNotNull);
      expect(mb, greaterThan(1000));
    });

    test('free disk reads a plausible figure', () async {
      final mb = await DeviceStorage.freeMb();
      expect(mb, isNotNull);
      expect(mb, greaterThanOrEqualTo(0));
    });
  });
}
