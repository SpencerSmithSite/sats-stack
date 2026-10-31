/// A picked statement's copy is deleted, and the user's own file never is
/// (audit A-7).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/shared/utils/picked_files.dart';

void main() {
  late Directory root;
  late Directory cache;
  late Directory documents;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('picked');
    cache = await Directory(
      '${root.path}/cache/file_picker',
    ).create(recursive: true);
    documents = await Directory('${root.path}/Documents').create();
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> discard(String path) =>
      discardPickedCopy(path, tempDirs: ['${root.path}/cache']);

  test("the app's copy in its cache is deleted", () async {
    final copy = File('${cache.path}/statement.pdf')..writeAsStringSync('x');
    await discard(copy.path);
    expect(copy.existsSync(), isFalse);
  });

  test("the user's own file is never deleted", () async {
    // What a desktop picker hands back: the file itself, where it lives.
    final mine = File('${documents.path}/statement.pdf')
      ..writeAsStringSync('mine');
    await discard(mine.path);
    expect(mine.readAsStringSync(), 'mine');
  });

  test('a path that only looks like it is inside is not', () async {
    final sibling = await Directory('${root.path}/cache-other').create();
    final f = File('${sibling.path}/a.csv')..writeAsStringSync('x');
    await discard(f.path);
    expect(f.existsSync(), isTrue);
  });

  test('a copy already gone is fine', () async {
    await discard('${cache.path}/gone.csv');
  });
}
