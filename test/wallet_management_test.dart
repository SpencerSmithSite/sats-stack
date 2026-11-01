/// Adding, rescanning and removing xpub wallets.
///
/// `ManageWalletsSheet` was the only re-sync UI and nothing opened it, so a
/// wallet was never refreshed after it was added. Re-adding the key to get
/// fresh data doubled the stack (rows are hashed per wallet), and a failed
/// first sync left an empty wallet behind, because the wallet is created
/// before the sync runs.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/transaction_service.dart';
import 'package:sats_stack/core/services/wallet_service.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/features/transactions/transactions_screen.dart';
import 'package:sats_stack/features/transactions/widgets/add_wallet_sheet.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

// BIP84 test vector, account m/84'/0'/0'.
const _zpub =
    'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
    'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';

Future<void> _addRow(AppDatabase db, int walletId, String hash) => db
    .into(db.transactions)
    .insert(
      TransactionsCompanion.insert(
        walletId: walletId,
        date: DateTime(2025, 3, 4),
        description: 'BTC $hash',
        amountSats: 50000,
        amountFiat: 40,
        fiatCurrency: 'USD',
        source: 'xpub',
        isBitcoin: const Value(true),
        dedupHash: hash,
      ),
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('WalletService', () {
    late AppDatabase db;
    late WalletService wallets;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      wallets = WalletService(db);
    });
    tearDown(() => db.close());

    test('a key already tracked is refused, whitespace and all', () async {
      await wallets.addXpubWallet(label: 'Cold', xpub: _zpub, color: '#F7931A');
      await expectLater(
        wallets.addXpubWallet(
          label: 'Cold again',
          xpub: '  $_zpub\n',
          color: '#F7931A',
        ),
        throwsA(
          isA<DuplicateWalletException>().having(
            (e) => e.existing.label,
            'existing',
            'Cold',
          ),
        ),
      );
      expect(await wallets.getXpubWallets(), hasLength(1));
    });

    test('a double tap tracks the key once', () async {
      // Audit D-12: the check and the insert were apart, so two adds at once
      // could both pass the check.
      final results = await Future.wait([
        for (var i = 0; i < 2; i++)
          wallets
              .addXpubWallet(label: 'Cold', xpub: _zpub, color: '#F7931A')
              .then<Object>((w) => w, onError: (Object e) => e),
      ]);

      expect(results.whereType<Wallet>(), hasLength(1));
      expect(results.whereType<DuplicateWalletException>(), hasLength(1));
      expect(await wallets.getXpubWallets(), hasLength(1));
    });

    test(
      'the stored key is trimmed, so the duplicate check can match',
      () async {
        final w = await wallets.addXpubWallet(
          label: 'Cold',
          xpub: ' $_zpub ',
          color: '#F7931A',
        );
        expect(w.xpub, _zpub);
      },
    );

    test('removing a wallet takes its rows and nobody else\'s', () async {
      final cold = await wallets.addXpubWallet(
        label: 'Cold',
        xpub: _zpub,
        color: '#F7931A',
      );
      final manual = (await wallets.getDefaultManual())!;
      await _addRow(db, cold.id, 'a');
      await _addRow(db, cold.id, 'b');
      await _addRow(db, manual.id, 'c');

      expect(await wallets.transactionCount(cold.id), 2);
      expect(await wallets.deleteXpubWallet(cold.id), 2);

      expect(await wallets.getXpubWallets(), isEmpty);
      final left = await db.select(db.transactions).get();
      expect(left.map((t) => t.dedupHash), ['c']);
    });

    test('a manual wallet cannot be removed this way', () async {
      final manual = (await wallets.getDefaultManual())!;
      await expectLater(
        wallets.deleteXpubWallet(manual.id),
        throwsArgumentError,
      );
      expect(await wallets.getDefaultManual(), isNotNull);
    });
  });

  group('screens', () {
    Future<void> setUpApp(WidgetTester tester, {http.Client? client}) async {
      await tester.runAsync(() async {
        app.db = AppDatabase.forTesting(NativeDatabase.memory());
        app.categoryService = CategoryService(app.db);
        app.transactionService = TransactionService(app.db);
        app.walletService = WalletService(app.db);
        app.btcPriceService = BtcPriceService(app.db);
        app.xpubService = XpubService(
          app.db,
          client: client ?? MockClient((_) async => http.Response('[]', 200)),
        );
        app.currencyNotifier = ValueNotifier('USD');
        app.showBtcPriceNotifier = ValueNotifier(false);
      });
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tearDownApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => app.db.close());
    }

    testWidgets('the wallet button lists wallets, and one can be removed', (
      tester,
    ) async {
      await setUpApp(tester);
      await tester.runAsync(() async {
        final w = await app.walletService.addXpubWallet(
          label: 'Cold',
          xpub: _zpub,
          color: '#F7931A',
        );
        await _addRow(app.db, w.id, 'a');
      });
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const TransactionsScreen()),
            ],
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.byTooltip('Bitcoin wallets'));
      await settle(tester);
      expect(find.text('Cold'), findsOneWidget);
      expect(find.text('Rescan'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove Cold'));
      await settle(tester);
      expect(
        find.textContaining('1 transaction will be deleted'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await settle(tester);

      expect(find.text('No xpub wallets yet. Add one below.'), findsOneWidget);
      final left = await tester.runAsync(
        () => app.db.select(app.db.transactions).get(),
      );
      expect(left, isEmpty);
      await tearDownApp(tester);
    });

    testWidgets('a failed first sync leaves no wallet behind', (tester) async {
      await setUpApp(
        tester,
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AddWalletSheet(
              xpubService: app.xpubService,
              walletService: app.walletService,
              btcPriceService: app.btcPriceService,
            ),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Extended public key'),
        _zpub,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Wallet label'),
        'Cold',
      );
      await tester.tap(find.text('Add & Sync Wallet'));
      // The syncing step spins until the request fails, so wait for the error
      // rather than for the frame to settle.
      final error = find.textContaining('Could not sync this wallet');
      for (var i = 0; i < 50 && error.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      expect(error, findsOneWidget);
      final wallets = await tester.runAsync(app.walletService.getXpubWallets);
      expect(wallets, isEmpty);
      await tearDownApp(tester);
    });
  });
}
