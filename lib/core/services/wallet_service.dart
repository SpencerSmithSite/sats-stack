import 'package:drift/drift.dart' show Value;
import '../database/database.dart';

class WalletService {
  WalletService(this._db);

  final AppDatabase _db;

  Stream<List<Wallet>> watchAll() => _db.select(_db.wallets).watch();

  Future<List<Wallet>> getAll() {
    return _db.select(_db.wallets).get();
  }

  Future<List<Wallet>> getXpubWallets() {
    return (_db.select(_db.wallets)..where((w) => w.type.equals('xpub'))).get();
  }

  /// Returns the first manual wallet, or null if none exists.
  Future<Wallet?> getDefaultManual() async {
    final result = await (_db.select(_db.wallets)
          ..where((w) => w.type.equals('manual'))
          ..limit(1))
        .getSingleOrNull();
    return result;
  }

  /// Creates a new xpub wallet and returns it.
  Future<Wallet> addXpubWallet({
    required String label,
    required String xpub,
    required String color,
  }) async {
    final id = await _db.into(_db.wallets).insert(
      WalletsCompanion.insert(
        label: label,
        type: 'xpub',
        xpub: Value(xpub),
        color: color,
      ),
    );
    return (_db.select(_db.wallets)..where((w) => w.id.equals(id))).getSingle();
  }
}
