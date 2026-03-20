import 'package:drift/drift.dart';

class AppSettings extends Table {
  TextColumn get key => text().withLength(min: 1, max: 100)();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
