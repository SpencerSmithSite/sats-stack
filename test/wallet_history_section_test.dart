/// Choosing the user's own Electrum server in Settings, including one with a
/// self-signed certificate (TODO item 11).
///
/// `fetchCertificateFingerprint` existed for the "trust this certificate?"
/// prompt, but nothing called it, so a self-signed server — which is what a
/// home node has — could not be used at all.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/bitcoin_data_source.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/features/settings/widgets/settings_widgets.dart';
import 'package:sats_stack/features/settings/widgets/wallet_history_section.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

/// `openssl x509 -noout -fingerprint -sha256` of the fixture.
const _fingerprint =
    '37:8D:67:E7:2F:0E:B8:AE:B1:55:3B:93:0A:06:B9:72:'
    '5E:C1:21:CC:F4:51:4C:53:0E:16:83:18:87:97:F7:D6';

/// Answers the handshake and the connection test.
void _electrum(Socket conn) {
  conn
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final req = jsonDecode(line) as Map<String, dynamic>;
        final result = switch (req['method']) {
          'server.version' => ['Fake 1.0', '1.4'],
          'server.banner' => 'Fake Fulcrum',
          'server.peers.subscribe' => const [],
          _ => null,
        };
        conn.writeln(jsonEncode({'id': req['id'], 'result': result}));
      }, onError: (_) {});
}

/// A tap whose handler runs on real time. What it starts uses real sockets,
/// and a TLS session begun from the test's fake clock never completes.
Future<void> _realTap(WidgetTester tester, Finder finder) =>
    tester.runAsync(() => tester.tap(finder));

Future<SecureServerSocket> _tlsServer() => SecureServerSocket.bind(
  InternetAddress.loopbackIPv4,
  0,
  SecurityContext()
    ..useCertificateChain('test/fixtures/electrum_test_cert.pem')
    ..usePrivateKey('test/fixtures/electrum_test_key.pem'),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('a self-signed server', () {
    late SecureServerSocket server;
    setUp(() async {
      server = await _tlsServer();
      server.listen(_electrum, onError: (_) {});
    });
    tearDown(() => server.close());

    test('is refused until its certificate is pinned', () async {
      final xpub = XpubService(db);
      await xpub.electrum.saveSettings(
        host: '127.0.0.1',
        port: server.port,
        ssl: true,
      );
      await expectLater(
        xpub.electrum.openSession(),
        throwsA(isA<HandshakeException>()),
      );

      final seen = await xpub.electrum.fetchCertificateFingerprint();
      expect(seen, _fingerprint.replaceAll(':', '').toLowerCase());

      await xpub.electrum.saveSettings(
        host: '127.0.0.1',
        port: server.port,
        ssl: true,
        certificateFingerprint: seen!,
      );
      expect(await xpub.electrum.testConnection(), contains('Fake Fulcrum'));
    });
  });

  group('the Settings section', () {
    /// Real sockets, so real time: pumps until [found] shows up, or gives up
    /// after five seconds and lets the expectation that follows fail.
    Future<void> settle(WidgetTester tester, Finder found) async {
      for (var i = 0; i < 50 && found.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
    }

    Future<XpubService> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final xpub = XpubService(db);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: WalletHistorySection(xpub: xpub, onChanged: () {}),
            ),
          ),
        ),
      );
      return xpub;
    }

    Future<void> fillIn(
      WidgetTester tester,
      int port, {
      bool tls = false,
    }) async {
      await tester.tap(find.text('My Electrum server'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Electrum server'),
        '127.0.0.1',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Port'), '$port');
      if (tls) await tester.tap(find.text('Use TLS'));
      await tester.pump();
      await _realTap(tester, find.text('Save and test'));
    }

    testWidgets('a reachable server becomes the source', (tester) async {
      final server =
          (await tester.runAsync(
            () => ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
          ))!;
      server.listen(_electrum);
      final xpub = await pump(tester);
      expect(xpub.dataSource, BitcoinDataSource.mempool);

      await fillIn(tester, server.port);
      await settle(tester, find.textContaining('Connected to 127.0.0.1'));

      expect(find.textContaining('Connected to 127.0.0.1'), findsOneWidget);
      expect(xpub.dataSource, BitcoinDataSource.electrum);
      await tester.runAsync(server.close);
    });

    testWidgets('a self-signed certificate is offered, and trusted', (
      tester,
    ) async {
      // Listening on real time, not the test's fake clock: the server's side
      // of a completed TLS handshake is never serviced from the fake zone.
      final server =
          (await tester.runAsync(
            () async =>
                (await _tlsServer())..listen(_electrum, onError: (_) {}),
          ))!;
      final xpub = await pump(tester);

      await fillIn(tester, server.port, tls: true);
      await settle(tester, find.text('Trust this server’s certificate?'));

      expect(find.text('Trust this server’s certificate?'), findsOneWidget);
      expect(find.text(_fingerprint), findsOneWidget);
      await _realTap(tester, find.text('Trust'));
      await settle(tester, find.textContaining('Connected to 127.0.0.1'));

      expect(find.textContaining('Connected to 127.0.0.1'), findsOneWidget);
      expect(xpub.dataSource, BitcoinDataSource.electrum);
      expect(xpub.electrum.pinnedFingerprint, isNotEmpty);
      await tester.runAsync(server.close);
    });

    testWidgets('declining leaves the source where it was', (tester) async {
      // Listening on real time, not the test's fake clock: the server's side
      // of a completed TLS handshake is never serviced from the fake zone.
      final server =
          (await tester.runAsync(
            () async =>
                (await _tlsServer())..listen(_electrum, onError: (_) {}),
          ))!;
      final xpub = await pump(tester);

      await fillIn(tester, server.port, tls: true);
      await settle(tester, find.text('Trust this server’s certificate?'));
      await _realTap(tester, find.text('Cancel'));
      await settle(tester, find.textContaining('not trusted'));

      expect(find.textContaining('not trusted'), findsOneWidget);
      expect(xpub.dataSource, BitcoinDataSource.mempool);
      expect(xpub.electrum.pinnedFingerprint, isEmpty);
      await tester.runAsync(server.close);
    });

    testWidgets('a bad port is caught before anything is saved', (
      tester,
    ) async {
      final xpub = await pump(tester);
      await fillIn(tester, 70000);
      await tester.pump();
      expect(find.text('Enter a port from 1 to 65535'), findsOneWidget);
      expect(xpub.electrum.isConfigured, isFalse);
    });
  });

  testWidgets('the routing banner names the Electrum server', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: DataRoutingBanner(usingDefault: true, electrumHost: 'node.lan'),
        ),
      ),
    );
    expect(find.text('Prices from public servers'), findsOneWidget);
    expect(find.text('→  Your Electrum server (node.lan)'), findsOneWidget);
    expect(
      find.textContaining('addresses go only to your Electrum'),
      findsOneWidget,
    );
  });

  testWidgets('fits a small phone at a large text size', (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1400),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: WalletHistorySection(
                xpub: XpubService(db),
                onChanged: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('My Electrum server'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
