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
}
