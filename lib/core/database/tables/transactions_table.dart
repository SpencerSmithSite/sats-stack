import 'package:drift/drift.dart';
import 'wallets_table.dart';

/// Indexes cover the columns the app actually filters and sorts on.
///
/// `date` carries every month range and the list ordering; `walletId` the
/// per-wallet breakdown; `category` the budget and analytics grouping;
/// `recurringPeriod` the launch-time scan for due series, which is a tiny
/// fraction of rows and so benefits most. `dedupHash` already has one from its
/// unique constraint.
@TableIndex(name: 'idx_transactions_date', columns: {#date})
@TableIndex(name: 'idx_transactions_wallet_id', columns: {#walletId})
@TableIndex(name: 'idx_transactions_category', columns: {#category})
@TableIndex(name: 'idx_transactions_recurring_period',
    columns: {#recurringPeriod})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get walletId => integer().references(Wallets, #id)();
  DateTimeColumn get date => dateTime()();
  TextColumn get description => text().withLength(min: 0, max: 500)();
  // Always whole satoshis; negative = spending, positive = income/received
  IntColumn get amountSats => integer()();
  RealColumn get amountFiat => real()();
  // ISO 4217 currency code e.g. 'USD'
  TextColumn get fiatCurrency => text().withLength(min: 3, max: 3)();
  TextColumn get category => text().nullable()();
  // 'xpub' | 'csv' | 'manual'
  TextColumn get source => text().withLength(min: 1, max: 10)();
  BoolColumn get isBitcoin =>
      boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  // SHA-256 of (date + amount + description) for deduplication
  TextColumn get dedupHash => text().unique()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  // Recurring transactions — both null for one-off entries
  // period: 'weekly' | 'monthly' | 'yearly'
  TextColumn get recurringPeriod => text().nullable()();
  // The date of the very first entry in this series (series identity key)
  DateTimeColumn get recurringAnchorDate => dateTime().nullable()();
}
