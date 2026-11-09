/// The price chip's age keeps up while nothing else changes (audit U-18).
///
/// The label was worked out only when something rebuilt the chip, and a
/// failed fetch changes nothing, so an offline user saw "just now" on an
/// hours-old price.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';
import 'package:sats_stack/shared/widgets/btc_price_chip.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('an old price stops saying "just now"', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final prices =
        BtcPriceService(db)
          ..priceNotifier.value = 97000
          ..lastFetchedAt = DateTime.now();
    app.currencyNotifier = ValueNotifier('USD');
    app.showBtcPriceNotifier = ValueNotifier(true);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: Center(child: BtcPriceChip(service: prices))),
      ),
    );
    expect(find.textContaining('just now'), findsOneWidget);

    // Two hours on with every fetch failing: nothing about the price changes,
    // so nothing but time can make the chip say how old it is.
    prices.lastFetchedAt = DateTime.now().subtract(const Duration(hours: 2));
    await tester.pump(const Duration(seconds: 31));
    expect(find.textContaining('2h ago'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
