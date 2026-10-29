/// The import consent gate, end to end through `ImportService.importFile`.
///
/// Consent used to be written at the tap, permanently, with no way to take it
/// back and nothing afterwards saying an upload had happened. These pin the
/// repaired behaviour: a yes is remembered only once an import completes, it
/// can be withdrawn, and the result says who read the file.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/shared/constants/app_constants.dart';

class _NoKeyStore extends SecureKeyStore {
  const _NoKeyStore();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

/// A hosted provider that answers from memory instead of the network.
class _FakeHosted extends OllamaService {
  _FakeHosted(super.db) : super(keyStore: const _NoKeyStore());

  /// Runs while the "upload" is in flight, so a test can cancel there.
  void Function()? duringSend;
  int sends = 0;

  @override
  AiProvider get activeProvider => AiProvider.claude;
  @override
  bool get sendsDataOffDevice => true;
  @override
  String? get activeDataRecipient => 'Anthropic';
  @override
  String? get selectedModel => 'test-model';
  @override
  Future<bool> isAvailable() async => true;

  @override
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) async* {
    sends++;
    duringSend?.call();
    yield '[{"date":"2026-03-01","amount":12.5,"direction":"debit",'
        '"description":"Coffee","currency":"USD"}]';
  }
}

void main() {
  late AppDatabase db;
  late _FakeHosted ollama;
  late ImportService importService;
  late int sourceId;
  late String csvPath;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ollama = _FakeHosted(db);
    importService = ImportService(db, ollama);
    sourceId = await db
        .into(db.importSources)
        .insert(
          ImportSourcesCompanion.insert(
            name: 'Card',
            type: 'bank',
            currency: 'USD',
          ),
        );
    final dir = await Directory.systemTemp.createTemp('consent_test');
    csvPath = '${dir.path}/statement.csv';
    await File(
      csvPath,
    ).writeAsString('Date,Description,Amount\n2026-03-01,Coffee,-12.50\n');
  });

  tearDown(() => db.close());

  Future<ImportResult> run({required bool answer}) => importService.importFile(
    filePath: csvPath,
    fileName: 'statement.csv',
    sourceId: sourceId,
    onOffDeviceConsent: (_) async => answer,
  );

  test('a completed import remembers the yes and says who read it', () async {
    final result = await run(answer: true);

    expect(ollama.sends, 1);
    expect(result.sentTo, 'Anthropic');
    expect(
      result.aiLabel,
      'Claude',
      reason: 'the preview used to say "Ollama AI" for every provider',
    );
    expect(await importService.offDeviceImportAllowed(), isTrue);
  });

  test('a cancelled import does not remember the yes', () async {
    ollama.duringSend = importService.cancelImport;

    await expectLater(
      run(answer: true),
      throwsA(isA<ImportCancelledException>()),
    );

    // It was written at the tap, so cancelling a second later still left
    // every future import uploading without asking.
    expect(await importService.offDeviceImportAllowed(), isFalse);
  });

  group('each import has its own cancel switch', () {
    test('a second import does not revive a cancelled first', () async {
      // The first import is waiting on its consent dialog when the user
      // cancels and starts another. The cancel flag lived on the service, so
      // the second import's start cleared it and the first, answered yes a
      // moment later, uploaded anyway.
      final firstToken = ImportCancelToken();
      final answer = Completer<bool>();
      final first = importService.importFile(
        filePath: csvPath,
        fileName: 'statement.csv',
        sourceId: sourceId,
        cancelToken: firstToken,
        onOffDeviceConsent: (_) => answer.future,
      );
      await Future<void>.delayed(Duration.zero);
      firstToken.cancel();

      final second = importService.importFile(
        filePath: csvPath,
        fileName: 'statement.csv',
        sourceId: sourceId,
        cancelToken: ImportCancelToken(),
        onOffDeviceConsent: (_) async => false,
      );
      answer.complete(true);

      await expectLater(first, throwsA(isA<ImportCancelledException>()));
      expect((await second).tierUsed, ImportTier.rules);
      expect(ollama.sends, 0, reason: 'nothing was uploaded');
    });

    test('cancelling one import leaves another running', () async {
      final a = ImportCancelToken();
      final b = ImportCancelToken();
      ollama.duringSend = a.cancel;
      final first = importService.importFile(
        filePath: csvPath,
        fileName: 'statement.csv',
        sourceId: sourceId,
        cancelToken: a,
        onOffDeviceConsent: (_) async => true,
      );
      await expectLater(first, throwsA(isA<ImportCancelledException>()));

      ollama.duringSend = null;
      final second = await importService.importFile(
        filePath: csvPath,
        fileName: 'statement.csv',
        sourceId: sourceId,
        cancelToken: b,
        onOffDeviceConsent: (_) async => true,
      );
      expect(second.transactions, hasLength(1));
    });
  });

  test('a no sends nothing and falls back to the local rules', () async {
    final result = await run(answer: false);

    expect(ollama.sends, 0);
    expect(result.sentTo, isNull);
    expect(result.tierUsed, ImportTier.rules);
    expect(result.transactions, hasLength(1));
    expect(await importService.offDeviceImportAllowed(), isFalse);
  });

  test('consent can be withdrawn, and the next import asks again', () async {
    await run(answer: true);
    expect(await importService.providersAllowedToReadImports(), [
      AiProvider.claude,
    ]);

    await importService.revokeOffDeviceImportConsent();
    expect(await importService.providersAllowedToReadImports(), isEmpty);

    var asked = false;
    await importService.importFile(
      filePath: csvPath,
      fileName: 'statement.csv',
      sourceId: sourceId,
      onOffDeviceConsent: (_) async => asked = true,
    );
    expect(asked, isTrue);
  });

  test(
    'a photo is refused before consent when the backend cannot see',
    () async {
      final onDevice = OllamaService(db, keyStore: const _NoKeyStore());
      await onDevice.setActiveProvider(AiProvider.appleIntelligence);
      final service = ImportService(db, onDevice);
      final photo = File('${File(csvPath).parent.path}/receipt.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF]);

      var asked = false;
      final result = await service.importImage(
        imagePath: photo.path,
        sourceId: sourceId,
        onOffDeviceConsent: (_) async => asked = true,
      );

      expect(asked, isFalse);
      // Was generic advice about llava; the real reason is the backend.
      expect(result.errorMessage, contains('cannot read images'));
    },
  );

  group('consent for a server the user chose is for that server', () {
    late OllamaService real;
    late ImportService service;

    setUp(() async {
      real = OllamaService(db, keyStore: const _NoKeyStore());
      service = ImportService(db, real);
      await real.setActiveProvider(AiProvider.ollama);
    });

    test('a yes for one host does not carry over to another', () async {
      await real.saveSettings(url: 'https://ollama.example.com:11434');
      expect(real.sendsDataOffDevice, isTrue);
      await service.setOffDeviceImportAllowed(true);
      expect(await service.offDeviceImportAllowed(), isTrue);

      // Consent was stored per provider, so it survived this.
      await real.saveSettings(url: 'https://someone-else.example.net');
      expect(await service.offDeviceImportAllowed(), isFalse);
    });

    test('a consent stored before it named a server is asked again', () async {
      await real.saveSettings(url: 'https://ollama.example.com:11434');
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: AppConstants.aiImportConsentKey(AiProvider.ollama.key),
              value: 'true',
            ),
          );
      expect(await service.offDeviceImportAllowed(), isFalse);
    });

    test('...but still stands for a hosted provider', () async {
      await real.setActiveProvider(AiProvider.claude);
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: AppConstants.aiImportConsentKey(AiProvider.claude.key),
              value: 'true',
            ),
          );
      expect(await service.offDeviceImportAllowed(), isTrue);
    });
  });
}
