import 'package:drift/drift.dart';

class AiConversations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get prompt => text()();
  TextColumn get response => text()();
  TextColumn get model => text().withLength(min: 1, max: 100)();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
