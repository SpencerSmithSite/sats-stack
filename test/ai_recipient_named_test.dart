/// Every control that sends financial figures to a hosted AI names who
/// receives them (audit A-5, A-6).
///
/// The dashboard insight named the recipient only before the first insight,
/// so with one cached the refresh icon alone sent the month to whichever
/// provider was now selected. The chat named no one at all, though every
/// question carries the figures.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/models/fx_rates.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/features/ai_chat/ai_chat_screen.dart';
import 'package:sats_stack/features/dashboard/widgets/ai_insight_card.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';
import 'package:sats_stack/shared/widgets/ai_privacy_disclosure.dart';

class _Keys extends SecureKeyStore {
  const _Keys();
  @override
  Future<String> read(String providerId) async =>
      providerId == 'anthropic' ? 'sk-ant-test' : '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('the dashboard insight', () {
    testWidgets('names the recipient while an insight is showing', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          AiInsightCard(
            aiEnabled: true,
            cachedInsight: 'You spent less on dining.',
            offDeviceRecipient: 'Anthropic',
            onRefresh: () {},
          ),
        ),
      );
      expect(
        find.textContaining('Refreshing sends last month'),
        findsOneWidget,
      );
      expect(find.textContaining('to Anthropic.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Refresh insight.*Anthropic')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('says nothing when nothing leaves the device', (tester) async {
      await tester.pumpWidget(
        host(
          AiInsightCard(
            aiEnabled: true,
            cachedInsight: 'You spent less on dining.',
            onRefresh: () {},
          ),
        ),
      );
      expect(find.textContaining('sends last month'), findsNothing);
    });

    testWidgets('still asks before the first insight', (tester) async {
      await tester.pumpWidget(
        host(
          AiInsightCard(
            aiEnabled: true,
            offDeviceRecipient: 'Anthropic',
            onRefresh: () {},
          ),
        ),
      );
      expect(find.text('Generate an insight'), findsOneWidget);
      expect(find.textContaining('Sends last month'), findsOneWidget);
    });
  });

  group('the chat', () {
    testWidgets('the note renders only for a recipient', (tester) async {
      await tester.pumpWidget(host(const AiRecipientNote(null)));
      expect(find.textContaining('Each question sends'), findsNothing);
      await tester.pumpWidget(host(const AiRecipientNote('Anthropic')));
      expect(find.textContaining('to Anthropic.'), findsOneWidget);
    });

    Future<void> openChat(WidgetTester tester, AiProvider provider) async {
      await tester.runAsync(() async {
        app.db = AppDatabase.forTesting(NativeDatabase.memory());
        app.btcPriceService = BtcPriceService(app.db);
        app.currencyNotifier = ValueNotifier('USD');
        app.dashboardService = DashboardService(
          app.db,
          rates: () => const FxRates(display: 'USD', btcPrices: {}),
        );
        app.ollamaService = OllamaService(app.db, keyStore: const _Keys());
        await app.ollamaService.loadSettings();
        await app.ollamaService.setActiveProvider(provider);
      });
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const AiChatScreen()),
      );
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
    }

    Future<void> closeChat(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => app.db.close());
    }

    // The provider's model list is answered here, not by Anthropic.
    http.Client models() => MockClient(
      (_) async => http.Response('{"data": [{"id": "claude-test"}]}', 200),
    );

    testWidgets('names the hosted provider above the input', (tester) async {
      await http.runWithClient(() async {
        await openChat(tester, AiProvider.claude);
        expect(find.byType(AiRecipientNote), findsOneWidget);
        expect(find.textContaining('Each question sends'), findsOneWidget);
        expect(find.textContaining('Anthropic'), findsWidgets);
        await closeChat(tester);
      }, models);
    });
  });
}
