/// A copied chat answer is cleared from the clipboard after a minute (audit
/// U-16).
///
/// It is full of the user's figures, and it stayed on the clipboard —
/// readable by any app that reads it — until something else was copied.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/shared/utils/brief_clipboard.dart';

void main() {
  testWidgets('copied, then cleared after a minute', (tester) async {
    final written = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          written.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await copyBriefly('You spent \$1,240 on dining.');
    expect(written, ['You spent \$1,240 on dining.']);

    await tester.pump(briefClipboardLife - const Duration(seconds: 1));
    expect(written, hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    expect(written, ['You spent \$1,240 on dining.', '']);
  });

  testWidgets('a second copy restarts the minute', (tester) async {
    final written = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          written.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await copyBriefly('first');
    await tester.pump(const Duration(seconds: 50));
    await copyBriefly('second');
    await tester.pump(const Duration(seconds: 50));
    // The first copy's timer would have cleared the second by now.
    expect(written, ['first', 'second']);
    await tester.pump(const Duration(seconds: 11));
    expect(written, ['first', 'second', '']);
  });
}
