import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sats_stack/core/services/device_memory.dart';
import 'package:sats_stack/core/services/device_storage.dart';
import 'package:sats_stack/core/services/inference/gemini_nano_backend.dart';

/// Exercises the Gemini Nano bridge against the real ML Kit GenAI API.
///
/// Run with:
///
///     flutter test integration_test/gemini_nano_test.dart -d <android-device>
///
/// Most of this passes on any Android, including an emulator with no AICore.
/// That is the point: the bridge has to report *why* it cannot answer, and
/// "this device has no AICore" must arrive as a clean `unavailable` rather than
/// as a crash or as the silence of an unregistered channel. Generation itself
/// skips unless the device really can run Nano.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Gemini Nano bridge', () {
    test('the platform channel is reachable and answers', () async {
      final report = await GeminiNanoBackend.availability(refresh: true);

      // The failure this catches: a channel-name mismatch, or MainActivity
      // never calling GeminiNanoBridge.register. Either surfaces as
      // MissingPluginException, which the Dart side maps to
      // `unsupportedPlatform` — indistinguishable from "not Android" unless
      // asserted here, on Android.
      expect(
        report.state,
        isNot(GeminiNanoState.unsupportedPlatform),
        reason: 'The bridge is not registered. Check that '
            'GeminiNanoBridge.register runs in MainActivity and that the '
            'channel names match the Dart side.',
      );
      expect(report.detail, isNotEmpty);
    });

    test('an unsupported device reports a reason rather than crashing',
        () async {
      final report = await GeminiNanoBackend.availability(refresh: true);

      // ML Kit throws outright on a device with no AICore, or with an unlocked
      // bootloader. The bridge catches that and turns it into a state; if the
      // catch were missing this would surface as a PlatformException.
      expect(GeminiNanoState.values, contains(report.state));
      expect(report.state, isNot(GeminiNanoState.unknown),
          reason: 'the bridge returned a reason string Dart does not map');
    });

    test('generates a real answer when Nano is actually available', () async {
      final report = await GeminiNanoBackend.availability(refresh: true);
      if (!report.isAvailable) {
        markTestSkipped('Gemini Nano unavailable: ${report.detail}');
        return;
      }

      const backend = GeminiNanoBackend();
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
      expect(chunks.every((c) => c.isNotEmpty), isTrue);
      // ML Kit emits deltas, not cumulative text — the opposite of Apple's
      // framework. If that ever changed, chunk 2 would contain chunk 1.
      if (chunks.length > 1 && chunks.first.length > 3) {
        expect(chunks[1].contains(chunks.first), isFalse,
            reason: 'chunks look cumulative; the bridge assumes deltas');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('Android device probes', () {
    // DeviceBridge.kt has no other coverage — these are the only things that
    // run its two methods.
    test('memory reads a plausible figure via ActivityManager', () async {
      final mb = await DeviceMemory.totalMb();
      expect(mb, isNotNull, reason: 'the device channel returned nothing');
      expect(mb, greaterThan(500));
      // The OS reports materially less than the advertised figure; the model
      // catalogue's thresholds are set against this number, not marketing.
      expect(mb, lessThan(1024 * 1024));
    });

    test('free disk reads a plausible figure via StatFs', () async {
      final mb = await DeviceStorage.freeMb();
      expect(mb, isNotNull, reason: 'the device channel returned nothing');
      expect(mb, greaterThanOrEqualTo(0));
    });
  });
}
