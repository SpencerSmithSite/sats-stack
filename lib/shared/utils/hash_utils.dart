import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Generates a deduplication hash for a transaction.
/// Uses SHA-256 of (date + amount + description) as a stable unique key.
abstract final class HashUtils {
  /// [salt] should be empty for CSV import deduplication (so duplicates are
  /// caught) and a unique timestamp for manual entries (so intentional
  /// duplicates are allowed).
  static String transactionDedupHash({
    required DateTime date,
    required double amount,
    required String description,
    String salt = '',
  }) {
    final input = '${date.toIso8601String()}|$amount|$description|$salt';
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  /// [hash] scoped to one wallet, so the same transaction can be a row in two
  /// wallets without the two colliding on the unique `dedupHash` index.
  ///
  /// Derived from the existing hash rather than added to its salt, because a
  /// stored xpub row keeps only the first eight characters of its txid: a
  /// migration could not recompute a salted hash, but it can apply this to
  /// the one already stored — so the move to wallet scoping keeps every row,
  /// and every category or note the user set on it.
  static String scopedToWallet(String hash, int walletId) =>
      sha256.convert(utf8.encode('$hash|wallet_$walletId')).toString();
}
