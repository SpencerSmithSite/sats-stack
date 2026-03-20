import 'package:drift/drift.dart';

class BtcPriceCache extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get priceUsd => real()();
  DateTimeColumn get fetchedAt => dateTime()();
}
