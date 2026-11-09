/// A failed response's body is read for a bounded time and size (audit A-13).
///
/// The hosted backend read it whole with no timeout, so a proxy that sent an
/// error status and then stalled left the chat — and the dashboard insight,
/// which has no cancel — waiting for good.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/services/inference/cloud_backend.dart';
import 'package:sats_stack/core/services/inference/inference_backend.dart';

void main() {
  test('a body that stalls gives what arrived, after the wait', () async {
    // Never closed: that is the point.
    // ignore: close_sinks
    final body = StreamController<List<int>>();
    body.add(utf8.encode('Bad gate'));
    final text = await readErrorBody(
      body.stream,
      wait: const Duration(milliseconds: 50),
    );
    expect(text, 'Bad gate');
    expect(body.hasListener, isFalse);
  });

  test('an endless body stops at the cap', () async {
    var sent = 0;
    final body = Stream<List<int>>.periodic(Duration.zero, (_) {
      sent++;
      return List.filled(1000, 0x61);
    });
    final text = await readErrorBody(body, maxBytes: 4096);
    expect(text, hasLength(4096));
    expect(sent, lessThan(10));
  });

  test('a whole body is read as before', () async {
    final text = await readErrorBody(
      Stream.fromIterable([
        utf8.encode('{"error":{"message":'),
        utf8.encode('"Overloaded"}}'),
      ]),
    );
    expect(text, '{"error":{"message":"Overloaded"}}');
  });

  test('a hosted chat fails, not hangs, when the error body stalls', () async {
    const backend = CloudBackend(
      provider: CloudProvider.anthropic,
      model: 'm',
      apiKey: 'k',
    );
    // Never closed: the proxy stalls after its first bytes.
    // ignore: close_sinks
    final body = StreamController<List<int>>();
    final client = MockClient.streaming((req, _) async {
      body.add(utf8.encode('upstream '));
      return http.StreamedResponse(body.stream, 502);
    });

    final clock = Stopwatch()..start();
    await expectLater(
      backend
          .chat([
            {'role': 'user', 'content': 'hi'},
          ], client: client)
          .toList()
          // Without the bound this never completes.
          .timeout(const Duration(seconds: 10)),
      throwsA(
        isA<InferenceException>().having(
          (e) => e.message,
          'message',
          contains('HTTP 502'),
        ),
      ),
    );
    expect(clock.elapsed, lessThan(const Duration(seconds: 7)));
  });
}
