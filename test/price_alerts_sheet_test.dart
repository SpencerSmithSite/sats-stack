/// Settings → General → Price alerts: add, list and delete, in the display
/// currency, saying plainly that nothing checks in the background.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/price_alert.dart';
import 'package:sats_stack/core/services/notification_service.dart';
import 'package:sats_stack/core/services/price_alert_service.dart';
import 'package:sats_stack/features/settings/widgets/price_alerts_sheet.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late PriceAlertService service;

  /// Lets drift's real I/O finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    String currency = 'USD',
    double? price = 95000,
  }) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = PriceAlertService(
        db,
        notifications: NotificationService(deliver: (_, _, _) async => true),
      );
      await service.load();
    });
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PriceAlertsSheet(
              service: service,
              currency: currency,
              priceFor: (c) => c == currency ? price : null,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => db.close());
  }

  Future<void> add(WidgetTester tester, String price) async {
    await tester.enterText(find.byType(TextField), price);
    await tester.tap(find.text('Add alert'));
    await settle(tester);
  }

  testWidgets('says it only checks while the app is open', (tester) async {
    await open(tester);
    expect(find.textContaining('only while Sats Stack is open'), findsOne);
    expect(find.textContaining('Nothing checks in the background'), findsOne);
    expect(find.text('No alerts yet.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('adds, lists and deletes an alert', (tester) async {
    await open(tester);
    expect(find.text('Price in USD'), findsOneWidget);

    await add(tester, '100000');
    expect(find.text('Above \$100,000'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(service.alerts.value.single.currency, 'USD');
    // Started below the level, so it is armed.
    expect(service.alerts.value.single.wasBeyond, isFalse);

    await tester.tap(find.text('Falls below'));
    await tester.pump();
    await add(tester, '80000,50');
    expect(find.text('Below \$80,000.50'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete alert above \$100,000'));
    await settle(tester);
    expect(find.text('Above \$100,000'), findsNothing);
    expect(service.alerts.value.single.direction, PriceAlertDirection.below);

    // Saved, not only shown.
    final reloaded = PriceAlertService(
      db,
      notifications: NotificationService(),
    );
    await tester.runAsync(reloaded.load);
    expect(reloaded.alerts.value.single.price, 80000.5);
    await close(tester);
  });

  testWidgets('is set in the display currency', (tester) async {
    await open(tester, currency: 'EUR', price: 88000);
    expect(find.text('Price in EUR'), findsOneWidget);
    await add(tester, '90000');
    expect(service.alerts.value.single.currency, 'EUR');
    expect(find.text('Above €90,000'), findsOneWidget);
    await close(tester);
  });

  testWidgets('warns when the price is already past the level', (tester) async {
    await open(tester);
    expect(find.text('Bitcoin is \$95,000 now.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '90000');
    await tester.pump();
    expect(find.textContaining('already above this'), findsOneWidget);
    await close(tester);
  });

  testWidgets('refuses a price of zero', (tester) async {
    await open(tester, price: null);
    await add(tester, '0');
    expect(find.text('Enter a price above zero'), findsOneWidget);
    expect(service.alerts.value, isEmpty);
    await close(tester);
  });

  testWidgets('a spent alert says so', (tester) async {
    await open(tester);
    await add(tester, '100000');
    await tester.runAsync(() => service.check({'USD': 100001}));
    await tester.pump();
    expect(find.textContaining('Reached'), findsOneWidget);
    expect(find.textContaining('will not notify again'), findsOneWidget);
    await close(tester);
  });
}
