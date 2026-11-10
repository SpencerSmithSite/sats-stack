/// Runs before every test file: no test may reach the internet.
///
/// `auto_category_test` was calling live price and AI endpoints, so it passed
/// or failed with the network, and leaked the test's requests to third
/// parties. Any connection to a non-loopback host now fails at once with a
/// message naming it; a test that needs a server answers from a `MockClient`
/// or a local one.
///
/// Covers every `HttpClient` request (http and https) and every plain
/// `Socket` — Electrum over TCP (audit P-6). A direct `SecureSocket.connect`
/// cannot be caught here: it goes straight to `RawSocket`, which no override
/// reaches. Electrum over TLS in a test must therefore use a local server,
/// as `wallet_history_section_test` does.
library;

import 'dart:async';
import 'dart:io';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  HttpOverrides.global = _LoopbackOnly();
  IOOverrides.global = _LoopbackSockets();
  await testMain();
}

/// Whether [host] — a name, an IP literal or an [InternetAddress] — is this
/// machine. An IP literal is parsed, not matched by prefix: `startsWith('127.')`
/// also let `127.example.com` through.
bool isLoopback(Object host) {
  if (host is InternetAddress) return host.isLoopback;
  final name = '$host'.toLowerCase();
  if (name == 'localhost' || name.endsWith('.localhost')) return true;
  final literal =
      name.startsWith('[') && name.endsWith(']')
          ? name.substring(1, name.length - 1)
          : name;
  return InternetAddress.tryParse(literal)?.isLoopback ?? false;
}

SocketException _refused(Object where) => SocketException(
  'Tests may not reach the network ($where). Answer it from a MockClient '
  'or a local server instead.',
);

class _LoopbackOnly extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      final host = uri.host;
      if (!isLoopback(host)) return Future.error(_refused(uri));
      return uri.scheme == 'https'
          ? SecureSocket.startConnect(host, uri.port, context: context)
          : Socket.startConnect(host, uri.port);
    };
    return client;
  }
}

final class _LoopbackSockets extends IOOverrides {
  @override
  Future<Socket> socketConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) {
    if (!isLoopback(host as Object)) {
      return Future.error(_refused('$host:$port'));
    }
    return super.socketConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout,
    );
  }

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
  }) {
    if (!isLoopback(host as Object)) {
      return Future.error(_refused('$host:$port'));
    }
    return super.socketStartConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
    );
  }
}
