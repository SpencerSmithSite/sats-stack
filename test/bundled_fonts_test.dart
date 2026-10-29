/// The bundled fonts are fonts.
///
/// `RobotoMono-*.ttf` had been GitHub HTML pages since the first commit — the
/// "download" link saved the page, not the file — so every monospaced figure
/// fell back to the system font and ~600 KB of HTML shipped in the app.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The weight class a TrueType file declares in its OS/2 table.
int _weightClass(Uint8List b) {
  final data = ByteData.sublistView(b);
  final tables = data.getUint16(4);
  for (var i = 0; i < tables; i++) {
    final rec = 12 + 16 * i;
    if (String.fromCharCodes(b.sublist(rec, rec + 4)) == 'OS/2') {
      return data.getUint16(data.getUint32(rec + 8) + 4);
    }
  }
  throw StateError('no OS/2 table');
}

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  for (final (file, weight) in [
    ('RobotoMono-Regular.ttf', 400),
    ('RobotoMono-Medium.ttf', 500),
  ]) {
    test('$file is a TrueType font of weight $weight', () {
      final bytes = File('assets/fonts/$file').readAsBytesSync();
      expect(bytes.sublist(0, 4), [0, 1, 0, 0], reason: 'sfnt version 1.0');
      expect(_weightClass(bytes), weight);
    });
  }

  test('the Medium face is declared as weight 500', () {
    // Without it Flutter files the face under 400 too, and a w500 style picks
    // whichever it registered last.
    expect(
      pubspec,
      contains(
        'asset: assets/fonts/RobotoMono-Medium.ttf\n          weight: 500',
      ),
    );
  });

  test('the licence ships with the font', () {
    expect(File('assets/fonts/OFL.txt').readAsStringSync(), contains('SIL'));
    expect(pubspec, contains('- assets/fonts/OFL.txt'));
  });
}
