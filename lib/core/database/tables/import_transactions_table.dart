import 'package:drift/drift.dart';

import 'import_sources_table.dart';

class ImportedTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceId => integer().references(ImportSources, #id)();
  DateTimeColumn get date => dateTime()();
  // Smallest unit: cents for fiat (e.g. USD), sats for BTC/SATS. Always positive.
  IntColumn get amountCents => integer()();
  // 'debit' (money leaving) or 'credit' (money arriving)
  TextColumn get direction => text()();
  TextColumn get description => text()();
  TextColumn get category => text().nullable()();
  // ISO 4217 currency code or 'SATS'
  TextColumn get currency => text()();
  // Original unmodified description from source file
  TextColumn get rawDescription => text()();
  // SHA-256(sourceId + date + amountCents + rawDescription) for deduplication
  TextColumn get importHash => text().unique()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
