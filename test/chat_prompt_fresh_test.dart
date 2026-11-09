/// Each question carries the figures as they are when it is asked (audit A-9).
///
/// The chat tab stays alive across tab switches, and its system prompt was
/// built once when it opened: after an import, an edit or a new month, the
/// model went on answering from the old figures.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/models/fx_rates.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/features/ai_chat/ai_chat_screen.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

class _NoKeys extends SecureKeyStore {
  const _NoKeys();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

/// A local model that records each request and answers it at once.
class _Model extends OllamaService {
  _Model(super.db) : super(keyStore: const _NoKeys());

  final requests = <List<Map<String, String>>>[];

  @override
  AiProvider get activeProvider => AiProvider.ollama;
  @override
  bool get sendsDataOffDevice => false;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<String>> listModels() async => ['local'];
  @override
  String? get selectedModel => 'local';

  @override
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) {
    requests.add(messages);
    return Stream.value('Noted.');
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('a purchase made between questions reaches the next prompt', (
    tester,
  ) async {
    late _Model model;
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.btcPriceService = BtcPriceService(app.db);
      app.currencyNotifier = ValueNotifier('USD');
      app.dashboardService = DashboardService(
        app.db,
        rates: () => const FxRates(display: 'USD', btcPrices: {}),
      );
      model = _Model(app.db);
      app.ollamaService = model;
    });
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const AiChatScreen()),
    );
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    await settle();

    Future<void> ask(String question) async {
      await tester.enterText(find.byType(TextField), question);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle();
    }

    String systemPrompt(int request) =>
        model.requests[request].firstWhere(
          (m) => m['role'] == 'system',
        )['content']!;

    await ask('How am I doing?');
    expect(model.requests, hasLength(1));
    expect(systemPrompt(0), isNot(contains('Entertainment')));

    // Recorded while the chat tab stays open.
    await tester.runAsync(() async {
      final wallet = await app.db.select(app.db.wallets).getSingle();
      await app.db
          .into(app.db.transactions)
          .insert(
            TransactionsCompanion.insert(
              walletId: wallet.id,
              date: DateTime.now(),
              description: 'Concert tickets',
              amountSats: 0,
              amountFiat: -180,
              fiatCurrency: 'USD',
              category: const Value('Entertainment'),
              source: 'manual',
              dedupHash: 'a9-concert',
            ),
          );
    });

    await ask('And now?');
    expect(model.requests, hasLength(2));
    expect(systemPrompt(1), contains('Entertainment'));
    expect(systemPrompt(1), contains('180'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  });
}
