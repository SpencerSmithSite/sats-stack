/// Statements are size-checked before they are read, and parsed off the UI
/// isolate (audit A-8).
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ImportService service;
  late Directory dir;
  late int source;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ImportService(db, OllamaService(db));
    dir = await Directory.systemTemp.createTemp('import');
    source = await service.createSource(
      name: 'Bank',
      type: 'bank',
      currency: 'GBP',
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a file over the limit is refused before it is read', () async {
    final big = File('${dir.path}/years.csv');
    final raf = big.openSync(mode: FileMode.write);
    // Sparse: 26 MB long without writing 26 MB.
    raf.setPositionSync(ImportService.maxStatementBytes + 1024 * 1024);
    raf.writeByteSync(0x0a);
    raf.closeSync();

    final result = await service.importFile(
      filePath: big.path,
      fileName: 'years.csv',
      sourceId: source,
    );
    expect(result.transactions, isEmpty);
    expect(result.errorMessage, contains('26 MB'));
    expect(result.errorMessage, contains('shorter date range'));
  });

  test('a CSV is read through the isolate and comes back whole', () async {
    final csv = File('${dir.path}/march.csv')..writeAsStringSync(
      'Date,Description,Amount\n'
      '01/03/2026,Coffee,-3.50\n'
      '02/03/2026,Salary,2500.00\n',
    );
    final result = await service.importFile(
      filePath: csv.path,
      fileName: 'march.csv',
      sourceId: source,
    );
    expect(result.transactions.map((t) => t.description), ['Coffee', 'Salary']);
  });

  test('PDF text is extracted in an isolate', () async {
    final document = PdfDocument();
    document.pages.add().graphics.drawString(
      '01/03/2026 Coffee shop 3.50',
      PdfStandardFont(PdfFontFamily.helvetica, 12),
    );
    final pdf = File('${dir.path}/statement.pdf')
      ..writeAsBytesSync(await document.save());
    document.dispose();

    final text = await service.extractPdfText(pdf.path);
    expect(text, contains('Coffee shop'));
  });

  test('parsing is the same function wherever it runs', () {
    expect(ImportService.parseCsvRows('﻿a;b\r\n1;2\r'), [
      ['a', 'b'],
      ['1', '2'],
    ]);
  });
}
