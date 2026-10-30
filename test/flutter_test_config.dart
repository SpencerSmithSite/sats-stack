/// Runs before every test file: no test may reach the internet.
///
/// `auto_category_test` was calling live price and AI endpoints, so it passed
/// or failed with the network, and leaked the test's requests to third
/// parties. Any connection to a non-loopback host now fails at once with a
/// message naming it; a test that needs a server answers from a `MockClient`
/// or a local one.
library;

import 'dart:async';
import 'dart:io';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  HttpOverrides.global = _LoopbackOnly();
  await testMain();
}

class _LoopbackOnly extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      final host = uri.host;
      final loopback =
          host == 'localhost' ||
          host == '::1' ||
          host.startsWith('127.') ||
          host.endsWith('.localhost');
      if (!loopback) {
        throw SocketException(
          'Tests may not reach the network ($uri). Answer it from a '
          'MockClient instead.',
        );
      }
      return uri.scheme == 'https'
          ? SecureSocket.startConnect(host, uri.port, context: context)
          : Socket.startConnect(host, uri.port);
    };
    return client;
  }
}
