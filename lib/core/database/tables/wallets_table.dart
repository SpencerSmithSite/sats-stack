import 'package:drift/drift.dart';

class Wallets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text().withLength(min: 1, max: 100)();
  // 'xpub' | 'manual'
  TextColumn get type => text().withLength(min: 1, max: 10)();
  TextColumn get xpub => text().nullable()();
  // hex color string e.g. '#F7931A'
  TextColumn get color => text().withLength(min: 7, max: 7)();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
