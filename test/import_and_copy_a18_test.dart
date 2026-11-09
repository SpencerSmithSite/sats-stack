/// Smaller import and export fixes (audit A-18).
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/fx_rates.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';
import 'package:sats_stack/screens/import/import_column_mapper_screen.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('the column mapper reads the whole date column', () {
    test('a UK file whose first days are all 12 or under', () {
      // The first three rows were all it looked at: month-first, and every
      // row from the 13th on was then rejected.
      expect(
        guessDateFormat([
          '01/03/2026',
          '05/03/2026',
          '11/03/2026',
          '25/03/2026',
        ]),
        'DD/MM/YYYY',
      );
    });

    test('a US file stays month-first', () {
      expect(guessDateFormat(['03/01/2026', '03/25/2026']), 'MM/DD/YYYY');
    });

    test('a total line does not stop the guess', () {
      expect(
        guessDateFormat(['2026-03-01', '2026-03-02', 'Total']),
        'YYYY-MM-DD',
      );
      expect(
        guessDateFormat(['01/03/26', '25/03/26', 'Closing balance']),
        'DD/MM/YY',
      );
    });

    test('nothing to go on', () {
      expect(guessDateFormat([]), isNull);
      expect(guessDateFormat(['Coffee', 'Rent', '01/03/2026']), isNull);
    });
  });

  group('summary CSV fields', () {
    test('plain text is left alone', () {
      expect(DashboardService.csvField('Food & Dining'), 'Food & Dining');
    });

    test('a comma, quote or line break is quoted', () {
      expect(
        DashboardService.csvField('Bills, utilities'),
        '"Bills, utilities"',
      );
      expect(DashboardService.csvField('The "fun" fund'), '"The ""fun"" fund"');
      expect(DashboardService.csvField('Two\nlines'), '"Two\nlines"');
    });

    test('a formula is written as text', () {
      expect(DashboardService.csvField('=1+1'), "'=1+1");
      expect(DashboardService.csvField('@SUM(A1)'), "'@SUM(A1)");
      expect(DashboardService.csvField('-5'), "'-5");
      expect(
        DashboardService.csvField('=HYPERLINK("http://x","y")'),
        '"\'=HYPERLINK(""http://x"",""y"")"',
      );
    });
  });

  test('the summary keeps a category with a comma in one column', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final wallet = await db.select(db.wallets).getSingle();
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            walletId: wallet.id,
            date: DateTime(2026, 3, 10),
            description: 'Electric',
            amountSats: 0,
            amountFiat: -80,
            fiatCurrency: 'USD',
            category: const Value('Bills, utilities'),
            source: 'manual',
            dedupHash: 'a18-bills',
          ),
        );
    final csv = await DashboardService(
      db,
      rates: () => const FxRates(display: 'USD', btcPrices: {}),
    ).exportMonthlySummary(month: DateTime(2026, 3), currency: 'USD');

    final row = csv.split('\n').firstWhere((l) => l.contains('Bills'));
    expect(row, startsWith('"Bills, utilities",'));
    expect(
      row.substring('"Bills, utilities",'.length).split(','),
      hasLength(4),
    );
  });
}
