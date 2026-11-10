/// Settings for the on-device models (audit T-1: no tests at all).
///
/// Pins the status line — ready or not, with the platform's reason, and the
/// re-check a user needs after switching the model on — and the Gemini Nano
/// download: its progress, finishing, and a failure that says why and lets
/// the user try again.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/inference/inference_backend.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/features/settings/widgets/on_device_ai_section.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  group('the status line', () {
    testWidgets('ready', (tester) async {
      await pump(
        tester,
        PlatformModelStatus(
          detail: 'Apple Intelligence is ready.',
          isReady: true,
          onRecheck: () {},
        ),
      );
      expect(find.text('Apple Intelligence is ready.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('not ready, and Check again asks once more', (tester) async {
      var rechecks = 0;
      await pump(
        tester,
        PlatformModelStatus(
          detail: 'Apple Intelligence is switched off.',
          isReady: false,
          onRecheck: () => rechecks++,
        ),
      );
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      await tester.tap(find.text('Check again'));
      expect(rechecks, 1);
    });
  });

  group('the Gemini Nano download', () {
    setUp(() {
      app.ollamaService = OllamaService(
        AppDatabase.forTesting(NativeDatabase.memory()),
        keyStore: const SecureKeyStore(),
      );
    });

    testWidgets('shows progress, then finishes', (tester) async {
      final progress = StreamController<int>();
      var finished = 0;
      await pump(
        tester,
        GeminiNanoDownloadSection(
          onFinished: () => finished++,
          download: () => progress.stream,
        ),
      );
      await tester.tap(find.text('Download Gemini Nano'));
      await tester.pump();

      // Size unknown: an indeterminate bar.
      progress.add(-1);
      await tester.pump();
      final bar = find.byType(LinearProgressIndicator);
      expect(tester.widget<LinearProgressIndicator>(bar).value, isNull);
      expect(find.textContaining('continues in the background'), findsOne);

      progress.add(40);
      await tester.pump();
      expect(tester.widget<LinearProgressIndicator>(bar).value, 0.4);

      await progress.close();
      await tester.pumpAndSettle();
      expect(finished, 1);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a failure says why, and the button comes back', (
      tester,
    ) async {
      var finished = 0;
      await pump(
        tester,
        GeminiNanoDownloadSection(
          onFinished: () => finished++,
          download:
              () => Stream.error(InferenceException('Not enough storage.')),
        ),
      );
      await tester.tap(find.text('Download Gemini Nano'));
      await tester.pumpAndSettle();
      expect(find.text('Not enough storage.'), findsOneWidget);
      expect(find.text('Download Gemini Nano'), findsOneWidget);
      expect(finished, 0);
    });

    testWidgets('off Android, the real download says so', (tester) async {
      await pump(tester, GeminiNanoDownloadSection(onFinished: () {}));
      await tester.tap(find.text('Download Gemini Nano'));
      await tester.pumpAndSettle();
      expect(
        find.text('Gemini Nano is only available on Android.'),
        findsOneWidget,
      );
    });
  });
}
