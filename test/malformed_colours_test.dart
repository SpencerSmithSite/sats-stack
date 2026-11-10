/// A malformed colour in the database shows a fallback, not a red screen
/// (audit U-22).
///
/// Eight hand-rolled parsers each did `int.parse(..., radix: 16)`, which
/// throws on a bad value, and a restored database can hold one. They are now
/// one, `CategoryPalette.parseHex`, which returns null; and the two copies of
/// the category icon map are one.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/wallet_service.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/features/settings/widgets/categories_sheet.dart';
import 'package:sats_stack/features/transactions/widgets/manage_wallets_sheet.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';
import 'package:sats_stack/shared/theme/category_icons.dart';

const _zpub =
    'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
    'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  Future<void> pump(WidgetTester tester, Widget sheet) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: SingleChildScrollView(child: sheet)),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tidy(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  testWidgets('a category with a malformed colour', (tester) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      // As a restored database file can hold it: Drift's own checks are on
      // the way in, and this did not come in through them.
      await db.customStatement(
        'INSERT INTO categories (name, icon, color) '
        "VALUES ('Hobbies', 'pets', 'not-a-colour')",
      );
    });
    await pump(tester, CategoriesSheet(categoryService: CategoryService(db)));
    expect(tester.takeException(), isNull);
    expect(find.text('Hobbies'), findsOneWidget);
    await tidy(tester);
  });

  testWidgets('a wallet with a malformed colour', (tester) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.customStatement(
        'INSERT INTO wallets (label, type, color, xpub) '
        "VALUES ('Cold', 'xpub', '#GGGGGG', '$_zpub')",
      );
    });
    await pump(
      tester,
      ManageWalletsSheet(
        xpubService: XpubService(db),
        walletService: WalletService(db),
        btcPriceService: BtcPriceService(db),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Cold'), findsOneWidget);
    await tidy(tester);
  });

  test('one icon map, with the fallback for an unknown name', () {
    expect(categoryIcons, hasLength(28));
    expect(categoryIcon('pets'), Icons.pets);
    expect(categoryIcon('no-such-icon'), Icons.receipt_long);
    expect(categoryIcon(null, fallback: Icons.circle), Icons.circle);
  });
}
