import 'package:drift/drift.dart';

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  // hex color string e.g. '#F7931A'
  TextColumn get color => text().withLength(min: 7, max: 7)();
  // Material icon name e.g. 'restaurant'
  TextColumn get icon => text().withLength(min: 1, max: 50)();
  BoolColumn get isSystem =>
      boolean().withDefault(const Constant(false))();
}
