import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/services/csv_import_service.dart';
import '../../../core/services/wallet_service.dart';
import '../../../core/services/btc_price_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';

class CsvImportSheet extends StatefulWidget {
  const CsvImportSheet({
    super.key,
    required this.csvImportService,
    required this.walletService,
    required this.btcPriceService,
  });

  final CsvImportService csvImportService;
  final WalletService walletService;
  final BtcPriceService btcPriceService;

  @override
  State<CsvImportSheet> createState() => _CsvImportSheetState();
}

enum _ImportStep { pick, preview, done }

class _CsvImportSheetState extends State<CsvImportSheet> {
  _ImportStep _step = _ImportStep.pick;
  bool _loading = false;
  String? _error;
  CsvImportResult? _result;
  int _importedCount = 0;

  Future<void> _pickFile() async {
    setState(() { _loading = true; _error = null; });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'CSV'],
        allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final path = picked.files.single.path;
      if (path == null) {
        setState(() { _loading = false; _error = 'Could not access file.'; });
        return;
      }
      final result = await widget.csvImportService.parseFile(path);
      setState(() {
        _result = result;
        _step = _ImportStep.preview;
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = 'Failed to read file: $e'; });
    }
  }

  Future<void> _confirm() async {
    final result = _result;
    if (result == null) return;
    setState(() => _loading = true);
    try {
      final wallet = await widget.walletService.getDefaultManual();
      if (wallet == null) {
        setState(() { _loading = false; _error = 'No account found. Restart the app.'; });
        return;
      }
      final count = await widget.csvImportService.importRows(
        rows: result.rows,
        walletId: wallet.id,
        btcPrice: widget.btcPriceService.priceNotifier.value,
      );
      setState(() {
        _importedCount = count;
        _step = _ImportStep.done;
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = 'Import failed: $e'; });
    }
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
              // Title row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    const Icon(Icons.upload_file_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _step == _ImportStep.done ? 'Import Complete' : 'Import CSV',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (_step == _ImportStep.preview)
                      TextButton(
                        onPressed: () => setState(() {
                          _step = _ImportStep.pick;
                          _result = null;
                          _error = null;
                        }),
                        child: const Text('Change file'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Body
              switch (_step) {
                _ImportStep.pick => _PickStep(
                    loading: _loading,
                    error: _error,
                    onPick: _pickFile,
                  ),
                _ImportStep.preview => _PreviewStep(
                    result: _result!,
                    loading: _loading,
                    error: _error,
                    onToggleRow: (index, value) => setState(() {
                      _result!.rows[index].include = value;
                    }),
                    onConfirm: _confirm,
                  ),
                _ImportStep.done => _DoneStep(
                    count: _importedCount,
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

// ── Step 1: Pick file ────────────────────────────────────────────────────────

class _PickStep extends StatelessWidget {
  const _PickStep({required this.loading, required this.error, required this.onPick});

  final bool loading;
  final String? error;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 140,
            decoration: BoxDecoration(
              color: AppColors.bitcoinOrange.withAlpha(15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.bitcoinOrange.withAlpha(60),
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: InkWell(
              onTap: loading ? null : onPick,
              borderRadius: BorderRadius.circular(16),
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_file_rounded,
                            size: 40, color: AppColors.bitcoinOrange),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to choose a CSV file',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.bitcoinOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Chase · BofA · Wells Fargo · Barclays · HSBC · Monzo',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Step 2: Preview ──────────────────────────────────────────────────────────

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({
    required this.result,
    required this.loading,
    required this.error,
    required this.onToggleRow,
    required this.onConfirm,
  });

  final CsvImportResult result;
  final bool loading;
  final String? error;
  final void Function(int index, bool value) onToggleRow;
  final VoidCallback onConfirm;

  String _formatName(BankFormat f) => switch (f) {
        BankFormat.chase => 'Chase',
        BankFormat.bofa => 'Bank of America',
        BankFormat.wellsFargo => 'Wells Fargo',
        BankFormat.barclays => 'Barclays',
        BankFormat.hsbc => 'HSBC',
        BankFormat.monzo => 'Monzo',
        BankFormat.generic => 'Generic',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = result.rows;
    final selectedCount = rows.where((r) => r.include && !r.isDuplicate).length;
    final dateFmt = DateFormat('MMM d, yyyy');
    final fiatFmt = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stats bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              _StatBadge(
                label: _formatName(result.format),
                color: AppColors.bitcoinOrange,
                icon: Icons.account_balance_outlined,
              ),
              const SizedBox(width: 8),
              _StatBadge(
                label: '${rows.length} rows',
                color: AppColors.success,
                icon: Icons.receipt_long_outlined,
              ),
              if (result.duplicateCount > 0) ...[
                const SizedBox(width: 8),
                _StatBadge(
                  label: '${result.duplicateCount} dupes',
                  color: AppColors.textSecondary,
                  icon: Icons.content_copy_outlined,
                ),
              ],
              if (result.parseErrorCount > 0) ...[
                const SizedBox(width: 8),
                _StatBadge(
                  label: '${result.parseErrorCount} skipped',
                  color: AppColors.danger,
                  icon: Icons.warning_amber_outlined,
                ),
              ],
            ],
          ),
        ),
        // Row list
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              final amountColor = row.amountFiat >= 0
                  ? AppColors.success
                  : AppColors.danger;
              return Opacity(
                opacity: row.isDuplicate ? 0.45 : 1.0,
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  value: row.include && !row.isDuplicate,
                  onChanged: row.isDuplicate
                      ? null
                      : (v) => onToggleRow(i, v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.description,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        fiatFmt.format(row.amountFiat),
                        style: AppTextStyles.monoSmall.copyWith(
                          color: amountColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Row(
                    children: [
                      Text(
                        dateFmt.format(row.date),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CategoryPill(category: row.category),
                      if (row.isDuplicate) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.textSecondary.withAlpha(40),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'duplicate',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
        // Confirm button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: FilledButton(
            onPressed: (loading || selectedCount == 0) ? null : onConfirm,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            child: loading
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('Import $selectedCount transaction${selectedCount == 1 ? '' : 's'}'),
          ),
        ),
      ],
    );
  }
}

// ── Step 3: Done ─────────────────────────────────────────────────────────────

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.count, required this.onClose});

  final int count;
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
            '$count transaction${count == 1 ? '' : 's'} imported',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Duplicates were automatically skipped.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
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

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(70), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.category});

  final String category;

  static const _colors = <String, Color>{
    'Food & Dining': Color(0xFFE24B4A),
    'Transport': Color(0xFFF7931A),
    'Housing': Color(0xFF888780),
    'Shopping': Color(0xFF888780),
    'Subscriptions': Color(0xFF888780),
    'Entertainment': Color(0xFF1D9E75),
    'Bitcoin': Color(0xFFF7931A),
    'Income': Color(0xFF1D9E75),
    'Other': Color(0xFF888780),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[category] ?? const Color(0xFF888780);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        category,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
