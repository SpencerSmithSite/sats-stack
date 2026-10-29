/// The manual column mapper reads the real header and real dates.
///
/// It took row 0 as the header, so an export opening with a title offered the
/// title as column names and read every mapped column against the wrong rows.
/// Its dates overflowed instead of being rejected — 25/12/2025 read as MM/DD
/// became a date in 2027 — and DD/MM only accepted `/`.
library;

import 'dart:io';

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

  ColumnMapping mapping(String format) => ColumnMapping(
    dateColumn: 0,
    descriptionColumn: 1,
    amountColumn: 2,
    dateFormat: format,
  );

  Future<List<DateTime>> dates(String csv, String format) async =>
      (await service.parseWithMapping(csv, mapping(format), currency: 'GBP') ??
              const <ParsedTransaction>[])
          .map((t) => t.date)
          .toList();

  test('the mapper is given the detected header, not the title', () async {
    final dir = await Directory.systemTemp.createTemp('mapper');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/export.csv')..writeAsStringSync(
      'Statement for account 1234\n'
      'Date,Description,Amount\n'
      '2026-03-01,Coffee,-3.50\n',
    );

    final result = await service.readCsvForManualMapping(
      file.path,
      'export.csv',
    );

    expect(result.csvHeaders, ['Date', 'Description', 'Amount']);
    expect(result.csvRows!.first, result.csvHeaders);
  });

  test('a mapping is applied from the detected header too', () async {
    final parsed = await service.parseWithMapping(
      'Statement for account 1234\n'
      'Date,Description,Amount\n'
      '2026-03-01,Coffee,-3.50\n',
      mapping('YYYY-MM-DD'),
      currency: 'GBP',
    );
    expect(parsed!.single.description, 'Coffee');
  });

  group('a date that does not exist in the chosen order is rejected', () {
    test('25/12/2025 as MM/DD is not a date in 2027', () async {
      expect(await dates('D,Desc,A\n25/12/2025,Gift,-10\n', 'MM/DD/YYYY'), []);
    });

    test('31 February is not 3 March', () async {
      expect(await dates('D,Desc,A\n2026-02-31,Rent,-10\n', 'YYYY-MM-DD'), []);
    });

    test('a valid date still parses', () async {
      expect(await dates('D,Desc,A\n12/25/2025,Gift,-10\n', 'MM/DD/YYYY'), [
        DateTime(2025, 12, 25),
      ]);
    });
  });

  test('DD/MM accepts dots and dashes as well as slashes', () async {
    const csv =
        'D,Desc,A\n'
        '25/12/2025,One,-1\n'
        '25.12.2025,Two,-1\n'
        '25-12-2025,Three,-1\n';
    expect(await dates(csv, 'DD/MM/YYYY'), [
      DateTime(2025, 12, 25),
      DateTime(2025, 12, 25),
      DateTime(2025, 12, 25),
    ]);
  });

  test('DD/MM/YY is offered and read', () async {
    expect(await dates('D,Desc,A\n25/12/25,Gift,-10\n', 'DD/MM/YY'), [
      DateTime(2025, 12, 25),
    ]);
  });
}
