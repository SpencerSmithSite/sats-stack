/// The guard in `flutter_test_config.dart` is in force.
///
/// Every other test passing proves nothing about it: a test that swallows a
/// network error passes either way, which is how `auto_category_test` was
/// reaching live endpoints unnoticed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('a request to the internet fails at once', () async {
    await expectLater(
      http.get(Uri.parse('https://mempool.space/api/v1/prices')),
      throwsA(
        isA<SocketException>().having(
          (e) => e.message,
          'message',
          contains('Tests may not reach the network'),
        ),
      ),
    );
  });

  test('loopback is still allowed', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen(
      (r) =>
          r.response
            ..write('ok')
            ..close(),
    );
    final response = await http.get(
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    expect(response.body, 'ok');
  });
}
