/// Mapping a statement's columns by hand (audit T-1: 8% line coverage).
///
/// Pins when Parse is allowed, that a role belongs to one column at a time,
/// that the date format is guessed from the column, what the preview reads,
/// and what Parse does: it opens the review screen with the rows it read,
/// and saves the mapping for the source only when asked to and when it read
/// something.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/screens/import/import_column_mapper_screen.dart';
import 'package:sats_stack/screens/import/import_preview_screen.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

class _NoKeys extends SecureKeyStore {
  const _NoKeys();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

/// A UK export whose first dates are all the 12th or earlier.
const _csv =
    'When,Payee,Value\n'
    '01/03/2026,Tesco,-23.40\n'
    '05/03/2026,Salary,2100.00\n'
    '25/03/2026,Pret,-6.95\n';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late int sourceId;

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.ollamaService = OllamaService(app.db, keyStore: const _NoKeys());
      app.importService = ImportService(app.db, app.ollamaService);
      app.btcPriceService = BtcPriceService(app.db);
      app.currencyNotifier = ValueNotifier('GBP');
      sourceId = await app.importService.createSource(
        name: 'Barclays',
        type: 'bank',
        currency: 'GBP',
      );
    });
    final lines = _csv.trim().split('\n');
    final rows = [for (final l in lines) l.split(',')];
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ImportColumnMapperScreen(
          result: ImportResult(
            transactions: const [],
            fileType: ImportFileType.csv,
            fileName: 'statement.csv',
            needsManualMapping: true,
            rawCsvContent: _csv,
            csvHeaders: rows.first,
            csvRows: rows,
          ),
          sourceId: sourceId,
          sourceName: 'Barclays',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Sets column [index]'s role to [label] through its dropdown.
  Future<void> assign(WidgetTester tester, int index, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(index));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  String roleOf(WidgetTester tester, int index) =>
      tester
          .widget<DropdownButton<String>>(
            find.byType(DropdownButton<String>).at(index),
          )
          .value!;

  bool parseEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text('Parse Transactions'),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            ),
          )
          .onPressed !=
      null;

  Future<String?> savedMapping(WidgetTester tester) async =>
      (await tester.runAsync(
        () =>
            (app.db.select(app.db.importSources)
              ..where((s) => s.id.equals(sourceId))).getSingle(),
      ))!.columnMapping;

  Future<void> tidy(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  }

  testWidgets('Parse waits for a date, a description and an amount', (
    tester,
  ) async {
    await open(tester);
    expect(parseEnabled(tester), isFalse);
    await assign(tester, 0, 'Date');
    await assign(tester, 1, 'Description');
    expect(parseEnabled(tester), isFalse);
    await assign(tester, 2, 'Amount (signed)');
    expect(parseEnabled(tester), isTrue);
    await tidy(tester);
  });

  testWidgets('a role moves rather than being held by two columns', (
    tester,
  ) async {
    await open(tester);
    await assign(tester, 0, 'Description');
    await assign(tester, 1, 'Description');
    expect(roleOf(tester, 0), 'skip');
    expect(roleOf(tester, 1), 'description');
    await tidy(tester);
  });

  testWidgets('the date format is read from the whole column', (tester) async {
    await open(tester);
    await assign(tester, 0, 'Date');
    // 25/03 can only be day-first, though the first rows are ambiguous.
    expect(find.text('Date Format'), findsOneWidget);
    expect(find.text('DD/MM/YYYY'), findsOneWidget);
    await tidy(tester);
  });

  testWidgets('the preview reads the rows as mapped', (tester) async {
    await open(tester);
    await assign(tester, 0, 'Date');
    await assign(tester, 1, 'Description');
    await assign(tester, 2, 'Amount (signed)');
    expect(find.text('Preview (first 3 rows)'), findsOneWidget);
    expect(find.text('Pret'), findsWidgets);
    await tidy(tester);
  });

  testWidgets('Parse opens the review, and saves the mapping', (tester) async {
    await open(tester);
    await assign(tester, 0, 'Date');
    await assign(tester, 1, 'Description');
    await assign(tester, 2, 'Amount (signed)');
    await tester.ensureVisible(find.text('Parse Transactions'));
    await tester.tap(find.text('Parse Transactions'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      if (find.byType(ImportPreviewScreen).evaluate().isNotEmpty) break;
    }
    expect(find.byType(ImportPreviewScreen), findsOneWidget);
    expect(find.text('Tesco'), findsWidgets);
    expect(await savedMapping(tester), contains('DD/MM/YYYY'));
    await tidy(tester);
  });

  testWidgets('unticked, the mapping is not saved', (tester) async {
    await open(tester);
    await assign(tester, 0, 'Date');
    await assign(tester, 1, 'Description');
    await assign(tester, 2, 'Amount (signed)');
    await tester.ensureVisible(find.text('Save mapping for "Barclays"'));
    await tester.tap(find.text('Save mapping for "Barclays"'));
    await tester.pump();
    await tester.ensureVisible(find.text('Parse Transactions'));
    await tester.tap(find.text('Parse Transactions'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      if (find.byType(ImportPreviewScreen).evaluate().isNotEmpty) break;
    }
    expect(find.byType(ImportPreviewScreen), findsOneWidget);
    expect(await savedMapping(tester), isNull);
    await tidy(tester);
  });
}
