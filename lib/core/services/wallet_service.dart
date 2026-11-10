import 'package:drift/drift.dart';
import '../database/database.dart';

class WalletService {
  WalletService(this._db);

  final AppDatabase _db;

  Future<List<Wallet>> getXpubWallets() {
    return (_db.select(_db.wallets)..where((w) => w.type.equals('xpub'))).get();
  }

  /// Every xpub wallet, re-emitted when one is added, renamed or removed.
  Stream<List<Wallet>> watchXpubWallets() {
    return (_db.select(_db.wallets)
          ..where((w) => w.type.equals('xpub'))
          ..orderBy([(w) => OrderingTerm.asc(w.createdAt)]))
        .watch();
  }

  /// The wallet already tracking [xpub] — this key as this address type —
  /// if any.
  ///
  /// Compared on the trimmed text, which is the key's canonical base58check
  /// encoding, and whose version bytes are the address type: a key and an
  /// address type together are one wallet (audit B-7), so the same account
  /// as a `zpub` and as a `ypub` are two. A plain `xpub` on Automatic matches
  /// only itself; the sync then picks a type no wallet tracks, or refuses.
  Future<Wallet?> findByXpub(String xpub) =>
      (_db.select(_db.wallets)
            ..where((w) => w.xpub.equals(xpub.trim()))
            ..limit(1))
          .getSingleOrNull();

  /// Returns the first manual wallet, or null if none exists.
  Future<Wallet?> getDefaultManual() async {
    final result =
        await (_db.select(_db.wallets)
              ..where((w) => w.type.equals('manual'))
              ..limit(1))
            .getSingleOrNull();
    return result;
  }

  /// Creates a new xpub wallet and returns it.
  ///
  /// Throws [DuplicateWalletException] if [xpub] is already tracked. Every
  /// wallet's rows are hashed per wallet, so a second wallet on the same key
  /// is not deduplicated against the first — it doubled the stack.
  ///
  /// [scriptTypeChosen] is whether the user picked the address type that
  /// [xpub]'s version bytes record, which a sync then never second-guesses.
  Future<Wallet> addXpubWallet({
    required String label,
    required String xpub,
    required String color,
    bool scriptTypeChosen = false,
  }) async {
    xpub = xpub.trim();
    // The check and the insert in one transaction. Drift runs transactions
    // one at a time, so a second add of the same key — a double tap — waits
    // for the first and then finds it. Apart, both could pass the check and
    // the stack was counted twice (audit D-12).
    return _db.transaction(() async {
      final existing = await findByXpub(xpub);
      if (existing != null) throw DuplicateWalletException(existing);
      final id = await _db
          .into(_db.wallets)
          .insert(
            WalletsCompanion.insert(
              label: label,
              type: 'xpub',
              xpub: Value(xpub),
              color: color,
              scriptTypeChosen: Value(scriptTypeChosen),
            ),
          );
      return (_db.select(_db.wallets)
        ..where((w) => w.id.equals(id))).getSingle();
    });
  }

  /// How many transactions belong to [walletId].
  Future<int> transactionCount(int walletId) async {
    final count = _db.transactions.id.count();
    final row =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([count])
              ..where(_db.transactions.walletId.equals(walletId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Removes an xpub wallet and every transaction synced into it.
  ///
  /// Those rows are a projection of the chain, so nothing is lost that a
  /// re-add would not bring back — except the user's edits to them, which is
  /// why the UI confirms first. Manual wallets are refused: the default one is
  /// the foreign key every hand-entered transaction needs.
  Future<int> deleteXpubWallet(int walletId) {
    return _db.transaction(() async {
      final wallet =
          await (_db.select(_db.wallets)
            ..where((w) => w.id.equals(walletId))).getSingleOrNull();
      if (wallet == null) return 0;
      if (wallet.type != 'xpub') {
        throw ArgumentError.value(walletId, 'walletId', 'not an xpub wallet');
      }
      final removed =
          await (_db.delete(_db.transactions)
            ..where((t) => t.walletId.equals(walletId))).go();
      await (_db.delete(_db.wallets)..where((w) => w.id.equals(walletId))).go();
      return removed;
    });
  }
}

/// [WalletService.addXpubWallet] was given a key that [existing] already
/// tracks.
class DuplicateWalletException implements Exception {
  const DuplicateWalletException(this.existing);
  final Wallet existing;
  @override
  String toString() =>
      'This key is already tracked as this address type, as '
      '"${existing.label}". Rescan it from the wallet list, or choose another '
      'address type.';
}
