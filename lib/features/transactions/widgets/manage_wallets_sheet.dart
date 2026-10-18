import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../core/services/btc_price_service.dart';
import '../../../core/services/wallet_service.dart';
import '../../../core/services/xpub_service.dart';
import '../../../shared/theme/app_colors.dart';
import 'add_wallet_sheet.dart';

/// Bottom sheet that lists existing xpub wallets (with per-wallet Rescan
/// buttons) and provides a shortcut to add a new xpub / zpub wallet.
class ManageWalletsSheet extends StatefulWidget {
  const ManageWalletsSheet({
    super.key,
    required this.xpubService,
    required this.walletService,
    required this.btcPriceService,
  });

  final XpubService xpubService;
  final WalletService walletService;
  final BtcPriceService btcPriceService;

  @override
  State<ManageWalletsSheet> createState() => _ManageWalletsSheetState();
}

enum _Step { list, syncing, done }

class _ManageWalletsSheetState extends State<ManageWalletsSheet> {
  _Step _step = _Step.list;
  String _syncStatus = '';
  XpubSyncResult? _syncResult;
  String? _syncingWalletLabel;

  Future<void> _rescan(Wallet wallet) async {
    setState(() {
      _step = _Step.syncing;
      _syncStatus = 'Starting rescan…';
      _syncingWalletLabel = wallet.label;
    });

    try {
      final result = await widget.xpubService.syncWallet(
        wallet: wallet,
        btcPriceService: widget.btcPriceService,
        onProgress: (status) {
          if (mounted) setState(() => _syncStatus = status);
        },
      );

      if (mounted) {
        setState(() {
          _syncResult = result;
          _step = _Step.done;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _Step.list;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rescan failed: $e')),
        );
      }
    }
  }

  void _openAddWallet() {
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddWalletSheet(
        xpubService: widget.xpubService,
        walletService: widget.walletService,
        btcPriceService: widget.btcPriceService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Wallets',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              switch (_step) {
                _Step.list => _ListBody(
                    walletService: widget.walletService,
                    onRescan: _rescan,
                    onAdd: _openAddWallet,
                  ),
                _Step.syncing => _SyncingBody(
                    walletLabel: _syncingWalletLabel ?? 'Wallet',
                    status: _syncStatus,
                  ),
                _Step.done => _DoneBody(
                    result: _syncResult!,
                    walletLabel: _syncingWalletLabel ?? 'Wallet',
                    onClose: () => Navigator.of(context).pop(),
                    onBack: () => setState(() {
                      _step = _Step.list;
                      _syncResult = null;
                    }),
                  ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

// ── List ──────────────────────────────────────────────────────────────────────

class _ListBody extends StatelessWidget {
  const _ListBody({
    required this.walletService,
    required this.onRescan,
    required this.onAdd,
  });

  final WalletService walletService;
  final Future<void> Function(Wallet) onRescan;
  final VoidCallback onAdd;

  Color _parseColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Wallet>>(
      future: walletService.getXpubWallets(),
      builder: (context, snapshot) {
        final wallets = snapshot.data ?? [];
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wallets.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Text(
                    'No xpub wallets yet. Add one below.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                for (final wallet in wallets)
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: _parseColor(wallet.color),
                    ),
                    title: Text(wallet.label,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      wallet.xpub != null
                          ? '${wallet.xpub!.substring(0, 12)}…'
                          : '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                    trailing: OutlinedButton.icon(
                      onPressed: () => onRescan(wallet),
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text('Rescan'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                const Divider(height: 1),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add xpub / zpub wallet'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Syncing ───────────────────────────────────────────────────────────────────

class _SyncingBody extends StatelessWidget {
  const _SyncingBody({required this.walletLabel, required this.status});

  final String walletLabel;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
      child: Column(
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text(
            'Rescanning $walletLabel…',
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Done ──────────────────────────────────────────────────────────────────────

class _DoneBody extends StatelessWidget {
  const _DoneBody({
    required this.result,
    required this.walletLabel,
    required this.onClose,
    required this.onBack,
  });

  final XpubSyncResult result;
  final String walletLabel;
  final VoidCallback onClose;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 56, color: AppColors.success),
          const SizedBox(height: 16),
          Text(
            walletLabel,
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            result.imported > 0
                ? '${result.imported} new transaction${result.imported == 1 ? '' : 's'} imported'
                : 'No new transactions found',
            style:
                theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Scanned ${result.addressesScanned} addresses'
            '${result.skipped > 0 ? ' · ${result.skipped} already imported' : ''}.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48)),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onClose,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48)),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
