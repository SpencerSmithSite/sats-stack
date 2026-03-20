import 'package:drift/drift.dart';

/// Permanent cache of daily BTC prices per currency.
/// Populated during xpub sync and queried to assign historically-accurate
/// fiat values to imported transactions.
class BtcPriceHistory extends Table {
  /// ISO date string 'YYYY-MM-DD'.
  TextColumn get date => text()();

  /// ISO 4217 currency code, uppercased e.g. 'USD'.
  TextColumn get currency => text()();

  /// BTC price in [currency] on [date].
  RealColumn get price => real()();

  @override
  Set<Column> get primaryKey => {date, currency};
}
