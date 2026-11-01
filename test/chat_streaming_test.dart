/// Streaming an AI answer rebuilds the answer, not the conversation
/// (audit A-10).
///
/// Each token used to `setState` the whole chat: every bubble was rebuilt —
/// each re-parsing its Markdown — and a new scroll animation started, once
/// per token. Measured by widget identity, as `dashboard_rebuild_test` does:
/// a bubble whose parent did not rebuild keeps the very same widget object.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
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
import 'package:sats_stack/shared/widgets/markdown_text.dart';

class _NoKeys extends SecureKeyStore {
  const _NoKeys();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

/// A local model whose answers the test feeds a token at a time.
class _Model extends OllamaService {
  _Model(super.db) : super(keyStore: const _NoKeys());

  StreamController<String>? current;

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
    // Closed by the test, which feeds it.
    // ignore: close_sinks
    final c = StreamController<String>();
    current = c;
    return c.stream;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('tokens rebuild the answer, not the earlier messages', (
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

    // A first exchange, finished.
    await ask('How am I doing?');
    model.current!
      ..add('You are doing ')
      ..add('fine.');
    await settle();
    await model.current!.close();
    await settle();
    expect(find.text('You are doing fine.'), findsOneWidget);

    MarkdownText firstAnswer() => tester.widget<MarkdownText>(
      find.byWidgetPredicate(
        (w) => w is MarkdownText && w.source == 'You are doing fine.',
      ),
    );
    // The second answer streams in, token by token. Sending adds a message,
    // which rebuilds the list once; the tokens after it must not.
    await ask('And this month?');
    final before = firstAnswer();
    for (final token in ['Spending ', 'is ', 'down ', '12%.']) {
      model.current!.add(token);
      await tester.pump();
      await tester.pump();
    }
    await settle();

    expect(find.textContaining('Spending is down 12%.'), findsOneWidget);
    expect(identical(firstAnswer(), before), isTrue);

    await model.current!.close();
    await settle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  });
}
