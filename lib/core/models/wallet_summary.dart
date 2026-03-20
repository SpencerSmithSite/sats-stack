import '../database/database.dart';

class WalletSummary {
  const WalletSummary({
    required this.wallet,
    required this.totalSats,
    required this.monthChangeSats,
    required this.monthIncomeFiat,
    required this.monthSpendFiat,
    required this.transactionCount,
  });

  final Wallet wallet;

  /// All-time net BTC sats held in this wallet.
  final int totalSats;

  /// Net BTC sats change in the selected month.
  final int monthChangeSats;

  /// Total fiat income in the selected month (positive transactions).
  final double monthIncomeFiat;

  /// Total fiat spending in the selected month (absolute value of negatives).
  final double monthSpendFiat;

  /// Total number of transactions ever recorded against this wallet.
  final int transactionCount;

  bool get hasBitcoin => totalSats != 0 || monthChangeSats != 0;
  bool get hasActivity => transactionCount > 0;
}
