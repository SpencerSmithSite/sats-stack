/// The import screen (audit T-1: 25% line coverage).
///
/// Pins the sources list — empty, a card, deleting one, forgetting its saved
/// column layout — and importing a file through a stand-in for the platform
/// file picker: a statement the rules read goes to review, one they cannot
/// goes to the column mapper, a PDF with no AI connected asks first, and a
/// cancelled pick does nothing.
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/screens/import/import_column_mapper_screen.dart';
import 'package:sats_stack/screens/import/import_file_screen.dart';
import 'package:sats_stack/screens/import/import_preview_screen.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

class _NoKeys extends SecureKeyStore {
  const _NoKeys();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

/// An on-device backend that is never available, so no AI tier runs and no
/// request leaves the test.
class _NoAi extends OllamaService {
  _NoAi(super.db) : super(keyStore: const _NoKeys());
  @override
  AiProvider get activeProvider => AiProvider.appleIntelligence;
  @override
  Future<bool> isAvailable() async => false;
}

/// Hands back [next] as the picked file, or nothing for a cancelled pick.
class _Picker extends FilePicker {
  PlatformFile? next;
  var opened = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    opened++;
    final file = next;
    return file == null ? null : FilePickerResult([file]);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late _Picker picker;
  late int sourceId;

  /// The screen with one source, or none.
  Future<void> open(WidgetTester tester, {bool withSource = true}) async {
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.ollamaService = _NoAi(app.db);
      app.importService = ImportService(app.db, app.ollamaService);
      app.btcPriceService = BtcPriceService(app.db);
      app.currencyNotifier = ValueNotifier('GBP');
      app.aiEnabledNotifier = ValueNotifier(false);
      dir = await Directory.systemTemp.createTemp('import_screen');
      if (withSource) {
        sourceId = await app.importService.createSource(
          name: 'Barclays',
          type: 'bank',
          currency: 'GBP',
        );
      }
    });
    FilePicker.platform = picker = _Picker();
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const ImportFileScreen()),
            GoRoute(
              path: '/settings',
              builder: (_, _) => const Scaffold(body: Text('Settings')),
            ),
          ],
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tidy(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await app.db.close();
      await dir.delete(recursive: true);
    });
  }

  /// Writes [contents] to a file named [name] and has the picker return it.
  Future<void> willPick(WidgetTester tester, String name, String contents) =>
      tester.runAsync(() async {
        final file = File('${dir.path}/$name')..writeAsStringSync(contents);
        picker.next = PlatformFile(
          name: name,
          path: file.path,
          size: file.lengthSync(),
        );
      });

  Future<void> importIt(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await settle(tester);
  }

  testWidgets('with no sources, it says how to start', (tester) async {
    await open(tester, withSource: false);
    expect(find.text('No import sources yet'), findsOneWidget);
    await tidy(tester);
  });

  testWidgets('a source card, and deleting it asks first', (tester) async {
    await open(tester);
    expect(find.text('Barclays'), findsOneWidget);

    await tester.tap(find.byTooltip('More options for Barclays'));
    await tester.pumpAndSettle();
    // No saved column layout, so nothing to forget.
    expect(find.text('Forget saved column layout'), findsNothing);
    await tester.tap(find.text('Delete source'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Source?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Barclays'), findsOneWidget);

    await tester.tap(find.byTooltip('More options for Barclays'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Barclays'), findsNothing);
    expect(find.text('No import sources yet'), findsOneWidget);
    await tidy(tester);
  });

  testWidgets('a saved column layout can be forgotten', (tester) async {
    await open(tester);
    await tester.runAsync(
      () => app.importService.saveColumnMapping(
        sourceId,
        ColumnMapping()
          ..dateColumn = 0
          ..descriptionColumn = 1
          ..amountColumn = 2,
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('More options for Barclays'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget saved column layout'));
    await settle(tester);
    expect(
      find.text('Barclays: the next import will work out the columns again'),
      findsOneWidget,
    );
    final source = await tester.runAsync(
      () =>
          (app.db.select(app.db.importSources)
            ..where((s) => s.id.equals(sourceId))).getSingle(),
    );
    expect(source!.columnMapping, isNull);
    await tidy(tester);
  });

  testWidgets('a statement the rules read goes to review', (tester) async {
    await open(tester);
    await willPick(
      tester,
      'statement.csv',
      'Date,Description,Amount\n'
          '2026-03-01,Coffee,-3.50\n'
          '2026-03-02,Salary,2100.00\n',
    );
    await importIt(tester);
    expect(picker.opened, 1);
    expect(find.byType(ImportPreviewScreen), findsOneWidget);
    expect(find.text('Coffee'), findsWidgets);
    await tidy(tester);
  });

  testWidgets('one they cannot read goes to the column mapper', (tester) async {
    await open(tester);
    await willPick(
      tester,
      'odd.csv',
      'Ref,Note,Figure\n'
          'A1,Coffee,x3.50\n'
          'A2,Salary,y2100\n',
    );
    await importIt(tester);
    expect(find.byType(ImportColumnMapperScreen), findsOneWidget);
    await tidy(tester);
  });

  testWidgets('a PDF with no AI connected asks first', (tester) async {
    await open(tester);
    await willPick(tester, 'statement.pdf', '%PDF-1.4');
    await importIt(tester);
    expect(find.text('No AI provider connected'), findsOneWidget);
    await tester.tap(find.text('Connect AI'));
    await settle(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(ImportPreviewScreen), findsNothing);
    await tidy(tester);
  });

  testWidgets('a cancelled pick does nothing', (tester) async {
    await open(tester);
    await importIt(tester);
    expect(picker.opened, 1);
    expect(find.byType(ImportPreviewScreen), findsNothing);
    expect(find.byType(ImportColumnMapperScreen), findsNothing);
    await tidy(tester);
  });
}

/// Real file and database I/O, so real time.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}
