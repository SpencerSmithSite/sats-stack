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
@TableIndex(
  name: 'idx_transactions_recurring_period',
  columns: {#recurringPeriod},
)
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
  BoolColumn get isBitcoin => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  // SHA-256 of (date + amount + description) for deduplication
  TextColumn get dedupHash => text().unique()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // Recurring transactions — both null for one-off entries
  // period: 'weekly' | 'monthly' | 'yearly'
  TextColumn get recurringPeriod => text().nullable()();
  // The date of the very first entry in this series — what every later
  // occurrence's date is derived from.
  DateTimeColumn get recurringAnchorDate => dateTime().nullable()();
  // Which series a row belongs to; shared by every instance of it. The
  // identity used to be derived from the description and amount, so editing
  // an instance split it off into a series of its own (schema v9).
  TextColumn get recurringSeriesId => text().nullable()();

  // Set by the user on a Bitcoin movement between their own wallets (schema
  // v12). Its sats still count — the stack is where the coins are — but its
  // fiat does not: a self-send is not income or spending, and without this an
  // xpub transfer counted as both.
  BoolColumn get isOwnTransfer =>
      boolean().withDefault(const Constant(false))();
}
