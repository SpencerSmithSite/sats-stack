import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/wallets_table.dart';
import 'tables/transactions_table.dart';
import 'tables/categories_table.dart';
import 'tables/budgets_table.dart';
import 'tables/settings_table.dart';
import 'tables/btc_price_cache_table.dart';
import 'tables/btc_price_history_table.dart';
import 'tables/ai_conversations_table.dart';
import 'tables/import_sources_table.dart';
import 'tables/import_transactions_table.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Wallets,
  Transactions,
  Categories,
  Budgets,
  AppSettings,
  BtcPriceCache,
  BtcPriceHistory,
  AiConversations,
  ImportSources,
  ImportedTransactions,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedSystemCategories();
          await _seedDefaultWallet();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(transactions, transactions.recurringPeriod);
            await m.addColumn(transactions, transactions.recurringAnchorDate);
          }
          if (from < 3) {
            await m.createTable(btcPriceHistory);
          }
          if (from < 4) {
            await m.createTable(importSources);
            await m.createTable(importedTransactions);
          }
        },
      );

  /// Deletes all user data and re-seeds the factory defaults.
  Future<void> resetAndReseed() async {
    await transaction(() async {
      await delete(aiConversations).go();
      await delete(importedTransactions).go();
      await delete(importSources).go();
      await delete(budgets).go();
      await delete(transactions).go();
      await delete(wallets).go();
      await delete(categories).go();
      await delete(btcPriceCache).go();
      await delete(btcPriceHistory).go();
      await delete(appSettings).go();
      await _seedSystemCategories();
      await _seedDefaultWallet();
    });
  }

  Future<void> _seedSystemCategories() async {
    final systemCategories = [
      CategoriesCompanion.insert(
        name: 'Food & Dining',
        color: '#E24B4A',
        icon: 'restaurant',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Transport',
        color: '#F7931A',
        icon: 'directions_car',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Housing',
        color: '#888780',
        icon: 'home',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Shopping',
        color: '#888780',
        icon: 'shopping_bag',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Subscriptions',
        color: '#888780',
        icon: 'subscriptions',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Entertainment',
        color: '#1D9E75',
        icon: 'movie',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Bitcoin',
        color: '#F7931A',
        icon: 'currency_bitcoin',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Income',
        color: '#1D9E75',
        icon: 'payments',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Other',
        color: '#888780',
        icon: 'more_horiz',
        isSystem: const Value(true),
      ),
    ];
    await batch((b) => b.insertAll(categories, systemCategories));
  }

  Future<void> _seedDefaultWallet() async {
    await into(wallets).insert(
      WalletsCompanion.insert(
        label: 'My Account',
        type: 'manual',
        color: '#F7931A',
      ),
    );
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'sats_stack_db');
}
