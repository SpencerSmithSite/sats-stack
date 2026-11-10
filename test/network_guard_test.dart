/// The test network guard covers raw sockets and parses IP literals (audit
/// P-6).
///
/// It overrode only `HttpClient`, while Electrum opens `Socket`s directly, so
/// a test could reach a real Electrum server unnoticed; and its
/// `startsWith('127.')` let `127.example.com` through.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'flutter_test_config.dart' show isLoopback;

void main() {
  test('a raw socket to the internet is refused', () async {
    await expectLater(
      Socket.connect('electrum.example.com', 50001),
      throwsA(
        isA<SocketException>().having(
          (e) => e.message,
          'message',
          contains('Tests may not reach the network'),
        ),
      ),
    );
  });

  test('a raw socket to this machine is allowed through', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final socket = await Socket.connect('127.0.0.1', server.port);
    socket.destroy();
  });

  test('loopback is read from the address, not its spelling', () {
    expect(isLoopback('localhost'), isTrue);
    expect(isLoopback('127.0.0.1'), isTrue);
    expect(isLoopback('127.4.5.6'), isTrue);
    expect(isLoopback('::1'), isTrue);
    expect(isLoopback('[::1]'), isTrue);
    expect(isLoopback(InternetAddress.loopbackIPv6), isTrue);
    expect(isLoopback('127.example.com'), isFalse);
    expect(isLoopback('mempool.space'), isFalse);
    expect(isLoopback('192.168.1.10'), isFalse);
  });

  test('an http request to a lookalike host is refused', () async {
    final client = HttpClient();
    addTearDown(client.close);
    await expectLater(
      client.getUrl(Uri.parse('http://127.example.com/')),
      throwsA(isA<SocketException>()),
    );
  });
}
