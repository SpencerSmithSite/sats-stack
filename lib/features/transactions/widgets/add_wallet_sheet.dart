import 'package:flutter/material.dart';
import '../../../core/services/xpub_service.dart';
import '../../../core/services/wallet_service.dart';
import '../../../core/services/btc_price_service.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../shared/theme/app_colors.dart';

class AddWalletSheet extends StatefulWidget {
  const AddWalletSheet({
    super.key,
    required this.xpubService,
    required this.walletService,
    required this.btcPriceService,
  });

  final XpubService xpubService;
  final WalletService walletService;
  final BtcPriceService btcPriceService;

  @override
  State<AddWalletSheet> createState() => _AddWalletSheetState();
}

enum _SheetStep { form, syncing, done }

class _AddWalletSheetState extends State<AddWalletSheet> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _xpubController = TextEditingController();

  _SheetStep _step = _SheetStep.form;
  String _selectedColor = '#F7931A';
  String _syncStatus = '';
  XpubSyncResult? _syncResult;
  String? _error;

  static const _colorOptions = [
    '#F7931A', // Bitcoin orange
    '#1D9E75', // Green
    '#6AB0E8', // Blue
    '#888780', // Grey
    '#E24B4A', // Red
  ];

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final extKey = _xpubController.text.trim();
    final label = _labelController.text.trim();

    setState(() {
      _step = _SheetStep.syncing;
      _syncStatus = 'Creating wallet…';
      _error = null;
    });

    try {
      final wallet = await widget.walletService.addXpubWallet(
        label: label,
        xpub: extKey,
        color: _selectedColor,
      );

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
          _step = _SheetStep.done;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _SheetStep.form;
          _error = 'Error: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _xpubController.dispose();
    super.dispose();
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
                  width: 36, height: 4,
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
                      _step == _SheetStep.done ? 'Wallet Added' : 'Add xpub Wallet',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              switch (_step) {
                _SheetStep.form => _FormBody(
                    formKey: _formKey,
                    labelController: _labelController,
                    xpubController: _xpubController,
                    selectedColor: _selectedColor,
                    colorOptions: _colorOptions,
                    error: _error,
                    xpubService: widget.xpubService,
                    onColorSelect: (c) => setState(() => _selectedColor = c),
                    onSubmit: _submit,
                  ),
                _SheetStep.syncing => _SyncingBody(status: _syncStatus),
                _SheetStep.done => _DoneBody(
                    result: _syncResult!,
                    onClose: () => Navigator.of(context).pop(),
                  ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

// ── Form ──────────────────────────────────────────────────────────────────────

class _FormBody extends StatelessWidget {
  const _FormBody({
    required this.formKey,
    required this.labelController,
    required this.xpubController,
    required this.selectedColor,
    required this.colorOptions,
    required this.error,
    required this.xpubService,
    required this.onColorSelect,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController labelController;
  final TextEditingController xpubController;
  final String selectedColor;
  final List<String> colorOptions;
  final String? error;
  final XpubService xpubService;
  final ValueChanged<String> onColorSelect;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // xpub field
            TextFormField(
              controller: xpubController,
              decoration: const InputDecoration(
                labelText: 'Extended public key',
                hintText: 'xpub… / ypub… / zpub…',
              ),
              maxLines: 2,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter an xpub, ypub, or zpub';
                final key = v.trim();
                if (!key.startsWith('xpub') &&
                    !key.startsWith('ypub') &&
                    !key.startsWith('zpub') &&
                    !key.startsWith('upub') &&
                    !key.startsWith('vpub')) {
                  return 'Must start with xpub, ypub, or zpub';
                }
                try {
                  xpubService.deriveAddresses(key, 0, 1);
                } catch (_) {
                  return 'Invalid extended key — check for typos';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            // Format hint
            ListenableBuilder(
              listenable: xpubController,
              builder: (_, __) {
                final text = xpubController.text.trim();
                if (text.isEmpty) return const SizedBox.shrink();
                String hint;
                if (text.startsWith('xpub')) hint = 'BIP44 · Legacy P2PKH';
                else if (text.startsWith('ypub')) hint = 'BIP49 · Nested SegWit P2SH-P2WPKH';
                else if (text.startsWith('zpub')) hint = 'BIP84 · Native SegWit P2WPKH';
                else return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.bitcoinOrange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Label
            TextFormField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: 'Wallet label',
                hintText: 'e.g. Cold Storage, Hardware Wallet…',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a label' : null,
            ),
            const SizedBox(height: 20),

            // Color picker
            Text(
              'Colour',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final hex in colorOptions) ...[
                  _ColorDot(
                    hex: hex,
                    selected: selectedColor == hex,
                    onTap: () => onColorSelect(hex),
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Privacy notice — content depends on whether a custom server is set
            Builder(builder: (context) {
              final esploraUrl = xpubService.esploraBaseUrl;
              final usingCustom = esploraUrl != AppConstants.mempoolBaseUrl;

              final isDark = Theme.of(context).brightness == Brightness.dark;
              if (usingCustom) {
                const accent = Color(0xFF6AC86A);
                // Custom server: show which server is being used, no warning
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: accent.withOpacity(isDark ? 0.35 : 0.20),
                        width: 0.5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 14, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Transactions will be fetched exclusively from your custom server ($esploraUrl). No data is sent to public servers.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: accent,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Default mempool.space: show the original privacy warning
              const accent = Color(0xFF6AB0E8);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withOpacity(isDark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: accent.withOpacity(isDark ? 0.35 : 0.20),
                      width: 0.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Transactions are fetched from mempool.space. Your xpub is stored locally only — never sent to any server.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: accent,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),

            FilledButton(
              onPressed: onSubmit,
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              child: const Text('Add & Sync Wallet'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Syncing ───────────────────────────────────────────────────────────────────

class _SyncingBody extends StatelessWidget {
  const _SyncingBody({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
      child: Column(
        children: [
          const SizedBox(
            width: 48, height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text(
            'Syncing…',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Done ──────────────────────────────────────────────────────────────────────

class _DoneBody extends StatelessWidget {
  const _DoneBody({required this.result, required this.onClose});

  final XpubSyncResult result;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 56, color: AppColors.success),
          const SizedBox(height: 16),
          Text(
            '${result.imported} transaction${result.imported == 1 ? '' : 's'} imported',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Scanned ${result.addressesScanned} addresses'
            '${result.skipped > 0 ? ' · ${result.skipped} duplicates skipped' : ''}.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: onClose,
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

// ── Color dot ─────────────────────────────────────────────────────────────────

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.hex, required this.selected, required this.onTap});

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  Color _parse(String hex) {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final color = _parse(hex);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withAlpha(100), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }
}
