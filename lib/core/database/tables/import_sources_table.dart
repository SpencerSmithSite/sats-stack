import 'package:drift/drift.dart';

class ImportSources extends Table {
  IntColumn get id => integer().autoIncrement()();
  // User-given name e.g. "Chase Checking"
  TextColumn get name => text()();
  // bank | credit_card | loan | bitcoin_exchange | bitcoin_wallet | other
  TextColumn get type => text()();
  // ISO 4217 or 'SATS'
  TextColumn get currency => text()();
  // JSON blob of saved ColumnMapping for Tier 3 reuse
  TextColumn get columnMapping => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
