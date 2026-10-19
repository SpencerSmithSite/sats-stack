/// The parsing gaps the import rework did not reach: number and date
/// conventions decided per file, statements with a preamble, and line endings.
///
/// Each of these failed silently — a wrong amount or date with nothing to tell
/// the user — which is why each is pinned with the value it used to produce.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';

void main() {
  late AppDatabase db;
  late ImportService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ImportService(db, OllamaService(db));
  });

  tearDown(() => db.close());

  Future<List<ParsedTransaction>> rules(String csv) async =>
      (await service.parseWithRules(csv, currency: 'EUR')) ?? const [];

  List<double> amounts(List<ParsedTransaction> txns) =>
      [for (final t in txns) t.amount];

  group('dot-grouped thousands', () {
    test('2.500 is two thousand five hundred in a decimal-comma file',
        () async {
      final txns = await rules('Date;Description;Amount\n'
          '2025-03-01;Rent;-2.500\n'
          '2025-03-02;Coffee;-3,50\n');
      // Was 2.5 — a 1000× understatement, with nothing to say so.
      expect(amounts(txns), [2500, 3.5]);
    });

    test('1.234.567 can only be grouping, whatever the file', () async {
      final txns = await rules('Date,Description,Amount\n'
          '2025-03-01,House,-1.234.567\n'
          '2025-03-02,Coffee,-3.50\n');
      // Used to be dropped: double.tryParse('1.234.567') is null.
      expect(amounts(txns), [1234567, 3.5]);
    });

    test('a BTC-style three-place decimal is left alone', () async {
      // The reason this is inferred, not a blanket mirror of the comma rule.
      final txns = await rules('Date,Description,Amount\n'
          '2025-03-01,Bought,1.500\n'
          '2025-03-02,Bought,0.12345678\n');
      expect(amounts(txns), [1.5, 0.12345678]);
    });

    test('with no decisive value the decimal-point reading stands', () async {
      final txns = await rules('Date,Description,Amount\n'
          '2025-03-01,Bought,2.500\n');
      expect(amounts(txns), [2.5]);
    });
  });

  group('day-first inference', () {
    test('is a vote, so one US row does not decide a UK file', () async {
      final txns = await rules('Date,Description,Amount\n'
          '04/15/2025,Imported US row,-1.00\n'
          '03/04/2025,Ambiguous,-2.00\n'
          '13/04/2025,UK,-3.00\n'
          '20/04/2025,UK,-4.00\n');
      final ambiguous = txns.firstWhere((t) => t.description == 'Ambiguous');
      // The first decisive row used to decide: month-first, so 4 March.
      expect(ambiguous.date, DateTime(2025, 4, 3));
      // Each row's own decisive component still wins for that row.
      expect(txns.first.date, DateTime(2025, 4, 15));
    });
  });

  group('file shape', () {
    test('a preamble before the header is skipped', () async {
      final txns = await rules('Account statement\n'
          'Account number,12345678\n'
          '\n'
          'Date,Description,Amount\n'
          '2025-03-04,Coffee,-3.50\n');
      // Row 0 was taken as the header, so no columns were found at all.
      expect(txns, hasLength(1));
      expect(txns.single.description, 'Coffee');
    });

    test('the delimiter is not decided by a title line', () async {
      final txns = await rules('Statement, March 2025, Current account\n'
          'Date;Description;Amount\n'
          '2025-03-04;Coffee;-3,50\n'
          '2025-03-05;Lunch;-12,00\n');
      expect(amounts(txns), [3.5, 12]);
    });

    test('bare \\r line endings are lines', () async {
      final txns = await rules(
          'Date,Description,Amount\r2025-03-04,Coffee,-3.50\r'
          '2025-03-05,Lunch,-12.00\r');
      // Was one enormous row.
      expect(txns, hasLength(2));
    });
  });

  group('the PDF heuristic tier', () {
    test('reads a UK statement day-first', () {
      final txns = service.parsePdfText('04/03/2025 TESCO STORES 12.50\n'
          '05/03/2025 COSTA COFFEE 3.20\n'
          '18/03/2025 TFL TRAVEL 6.80\n');
      // Was booked as 3 April: this tier always parsed month-first.
      expect(txns.first.date, DateTime(2025, 3, 4));
    });

    test('reads a dotted German date and amount', () {
      final txns = service.parsePdfText('01.02.2025 Miete 1.234,56\n'
          '03.02.2025 Supermarkt 45,10\n'
          '14.02.2025 Tankstelle 60,00\n');
      // A dotted date used to match nothing, so every line was dropped.
      expect(txns, hasLength(3));
      expect(txns.first.date, DateTime(2025, 2, 1));
      expect(amounts(txns), [1234.56, 45.10, 60.00]);
    });
  });
}
