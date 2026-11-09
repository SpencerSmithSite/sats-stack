/// Get Started runs once at a time, and says when it fails (audit U-20).
///
/// A second tap while the first was still saving ran every write again, and
/// a keychain or database error escaped uncaught, leaving the user on the
/// last page with nothing said.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/features/onboarding/onboarding_screen.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

class _NoKeys extends SecureKeyStore {
  const _NoKeys();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

/// Saving the server waits on [gate], then fails if [error] is set.
class _Xpub extends XpubService {
  _Xpub(super.db);
  var saves = 0;
  final gate = Completer<void>();
  Error? error;

  @override
  Future<String?> saveSettings({required String url}) async {
    saves++;
    await gate.future;
    if (error case final e?) throw e;
    return null;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<_Xpub> onLastPage(WidgetTester tester) async {
    late _Xpub xpub;
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.ollamaService = OllamaService(app.db, keyStore: const _NoKeys());
      await app.ollamaService.loadSettings();
      app.xpubService = xpub = _Xpub(app.db);
      app.btcPriceService = BtcPriceService(app.db);
      app.currencyNotifier = ValueNotifier('USD');
      app.themeModeNotifier = ValueNotifier(ThemeMode.dark);
      app.onboardingCompleteNotifier = ValueNotifier(false);
      app.aiEnabledNotifier = ValueNotifier(false);
    });
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const OnboardingScreen()),
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: Text('Dashboard')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
    while (find.text('Get Started').evaluate().isEmpty) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    return xpub;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> tidy(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  }

  testWidgets('a second tap while saving does nothing', (tester) async {
    final xpub = await onLastPage(tester);
    await tester.tap(find.text('Get Started'));
    await tester.pump();
    await tester.tap(find.text('Get Started'), warnIfMissed: false);
    await tester.pump();
    xpub.gate.complete();
    await settle(tester);

    expect(xpub.saves, 1);
    expect(find.text('Dashboard'), findsOneWidget);
    await tidy(tester);
  });

  testWidgets('a failure is shown, and Get Started works again', (
    tester,
  ) async {
    final xpub = await onLastPage(tester);
    xpub.error = StateError('database is locked');
    await tester.tap(find.text('Get Started'));
    await tester.pump();
    xpub.gate.complete();
    await settle(tester);

    expect(find.textContaining("Couldn't finish setting up"), findsOneWidget);
    expect(find.textContaining('database is locked'), findsOneWidget);
    expect(app.onboardingCompleteNotifier.value, isFalse);
    // Still on the last page, with the button live again.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Get Started'),
    );
    expect(button.onPressed, isNotNull);
    await tidy(tester);
  });
}
