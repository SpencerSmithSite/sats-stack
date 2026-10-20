/// Opening an Electrum session, against a local server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/electrum_service.dart';

void main() {
  late AppDatabase db;
  late ServerSocket server;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    await server.close();
    await db.close();
  });

  test('a refused handshake closes the socket it opened', () async {
    // A server that rejects the protocol version and then waits, so the only
    // way the connection ends is the client closing it.
    final clientClosed = Completer<void>();
    server.listen((conn) {
      conn
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final id = (jsonDecode(line) as Map<String, dynamic>)['id'];
              conn.writeln(
                jsonEncode({
                  'id': id,
                  'error': {'message': 'unsupported protocol version'},
                }),
              );
            },
            onDone: () {
              if (!clientClosed.isCompleted) clientClosed.complete();
            },
          );
    });

    final electrum = ElectrumService(db);
    await electrum.saveSettings(
      host: '127.0.0.1',
      port: server.port,
      ssl: false,
    );

    await expectLater(electrum.openSession(), throwsA(anything));
    // Was never closed: the session that owned it was dropped on the throw.
    await clientClosed.future.timeout(const Duration(seconds: 5));
  });
}
