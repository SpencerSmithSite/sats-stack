/// A saved column mapping reads a single amount column the way the rules tier
/// does (audit A-4).
///
/// It read every signed figure as "negative is money out" and every unsigned
/// one as spending. A card that writes purchases as positive amounts (Amex)
/// had every purchase booked as income — and a saved mapping is the first
/// tier tried on every later import of its source.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ImportService service;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ImportService(db, OllamaService(db));
  });
  tearDown(() => db.close());

  final mapping = ColumnMapping(
    dateColumn: 0,
    descriptionColumn: 1,
    amountColumn: 2,
    dateFormat: 'YYYY-MM-DD',
  );

  Future<Map<String, String>> directions(String csv, String type) async {
    final source = await service.createSource(
      name: 'Account',
      type: type,
      currency: 'USD',
    );
    final rows = await service.parseWithMapping(csv, mapping, sourceId: source);
    return {for (final r in rows!) r.description: r.direction};
  }

  const amexStyle =
      'Date,Description,Amount\n'
      '2026-03-01,Coffee shop,4.50\n'
      '2026-03-02,Grocer,62.10\n'
      '2026-03-03,Fuel,40.00\n'
      '2026-03-20,Payment thank you,-106.60\n';

  test('a card that signs purchases positive books them as spending', () async {
    expect(await directions(amexStyle, 'credit_card'), {
      'Coffee shop': 'debit',
      'Grocer': 'debit',
      'Fuel': 'debit',
      'Payment thank you': 'credit',
    });
  });

  test('a card that signs purchases negative still reads right', () async {
    const chaseStyle =
        'Date,Description,Amount\n'
        '2026-03-01,Coffee shop,-4.50\n'
        '2026-03-02,Grocer,-62.10\n'
        '2026-03-20,Payment thank you,66.60\n';
    expect(await directions(chaseStyle, 'credit_card'), {
      'Coffee shop': 'debit',
      'Grocer': 'debit',
      'Payment thank you': 'credit',
    });
  });

  test('a bank account keeps "negative is money out"', () async {
    expect(await directions(amexStyle, 'bank'), {
      'Coffee shop': 'credit',
      'Grocer': 'credit',
      'Fuel': 'credit',
      'Payment thank you': 'debit',
    });
  });

  test('an unsigned column marked CR reads CR as the credits', () async {
    const ukCard =
        'Date,Description,Amount\n'
        '2026-03-01,Coffee shop,4.50\n'
        '2026-03-20,Payment received,100.00 CR\n';
    expect(await directions(ukCard, 'credit_card'), {
      'Coffee shop': 'debit',
      'Payment received': 'credit',
    });
  });

  test('an unsigned column catches an unmistakable credit', () async {
    const savings =
        'Date,Description,Amount\n'
        '2026-03-01,Coffee shop,4.50\n'
        '2026-03-25,Salary ACME Ltd,2500.00\n';
    final read = await directions(savings, 'bank');
    expect(read['Coffee shop'], 'debit');
    expect(read['Salary ACME Ltd'], 'credit');
  });
}
