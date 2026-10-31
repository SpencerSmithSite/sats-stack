import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/import_service.dart';
import '../../features/transactions/widgets/transaction_edit_sheet.dart';
import '../../main.dart' as app;
import '../../shared/theme/app_colors.dart';
import 'import_summary_screen.dart';

class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({
    super.key,
    required this.result,
    required this.sourceId,
    required this.sourceName,
  });

  final ImportResult result;
  final int sourceId;
  final String sourceName;

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  late List<ParsedTransaction> _txns;
  final Set<ParsedTransaction> _editedTxns = {};
  bool _importing = false;

  /// "Pricing 12 of 300 days" while historical prices are fetched — which
  /// for a long statement is most of the wait.
  String? _progress;

  /// Rows that look already imported from this source, unticked. Null until
  /// the check has run, and Import waits for it: a quick tap must not import
  /// them before they are unticked.
  int? _likelyDuplicates;

  @override
  void initState() {
    super.initState();
    _txns = List.of(widget.result.transactions);
    _checkDuplicates();
  }

  Future<void> _checkDuplicates() async {
    var marked = 0;
    try {
      marked = await app.importService.markLikelyDuplicates(
        _txns,
        widget.sourceId,
      );
    } catch (_) {
      // The save step's own hash still catches an exact re-import.
    }
    if (mounted) setState(() => _likelyDuplicates = marked);
  }

  int get _includeCount => _txns.where((t) => t.include).length;

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final summary = await app.importService.saveTransactions(
        transactions: _txns,
        sourceId: widget.sourceId,
        sourceName: widget.sourceName,
        btcPriceService: app.btcPriceService,
        btcPrice: app.btcPriceService.priceNotifier.value,
        onPricingProgress: (done, total) {
          if (mounted && total > 1) {
            setState(() => _progress = 'Pricing day ${done + 1} of $total…');
          }
        },
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ImportSummaryScreen(summary: summary),
          ),
          // Tells the column mapper, if it opened this, that the import is
          // done.
          result: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _progress = null;
        });
      }
    }
  }

  void _editTransaction(int index) {
    final tx = _txns[index];
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => TransactionEditSheet.forParsed(
            tx,
            onSaved: () => setState(() => _editedTxns.add(tx)),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasTransactions = _txns.isNotEmpty;

    // Date range
    DateTime? start, end;
    for (final t in _txns) {
      if (start == null || t.date.isBefore(start)) start = t.date;
      if (end == null || t.date.isAfter(end)) end = t.date;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview Import'),
        actions: [
          if (hasTransactions)
            TextButton(
              onPressed: () {
                setState(() {
                  final allOn = _txns.every((t) => t.include);
                  for (final t in _txns) {
                    t.include = !allOn;
                  }
                });
              },
              child: Text(
                _txns.every((t) => t.include) ? 'Deselect All' : 'Select All',
              ),
            ),
        ],
      ),
      body:
          hasTransactions
              ? Column(
                children: [
                  // Header card
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.sourceName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_txns.length} transaction${_txns.length != 1 ? 's' : ''} found'
                          '${start != null ? '  ·  ${DateFormat('MMM d, yyyy').format(start)} – ${DateFormat('MMM d, yyyy').format(end!)}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        if (widget.result.tierUsed != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Parsed via ${_tierLabel(widget.result.tierUsed!)}',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: cs.primary),
                          ),
                        ],
                        if (_likelyDuplicates case final n? when n > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            n == 1
                                ? '1 looks already imported, so it is '
                                    'unticked. Tick it if it is new.'
                                : '$n look already imported, so they are '
                                    'unticked. Tick any that are new.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (widget.result.sentTo != null) ...[
                          const SizedBox(height: 4),
                          _SentToNote(recipient: widget.result.sentTo!),
                        ],
                        if (widget.result.aiInputTruncatedAt
                            case final chars?) ...[
                          const SizedBox(height: 4),
                          Text(
                            'This file was too long to read in one go: only '
                            'its first ${NumberFormat.decimalPattern().format(chars)} '
                            'characters were sent, so later rows may be '
                            'missing. Import it in parts, or as a CSV.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (widget.result.aiOutputCutOff) ...[
                          const SizedBox(height: 4),
                          Text(
                            "The AI's answer was cut off partway, so some "
                            'rows may be missing. Check the list against '
                            'your statement.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (widget.result.tierUsed ==
                            ImportTier.pdfHeuristic) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Transactions extracted without AI — please review carefully before importing.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: Colors.orange),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Transaction list
                  Expanded(
                    child: ListView.builder(
                      itemCount: _txns.length,
                      itemBuilder: (context, i) {
                        final tx = _txns[i];
                        final isCredit = tx.direction == 'credit';
                        return Opacity(
                          opacity: tx.include ? 1.0 : 0.4,
                          child: ListTile(
                            leading: Checkbox(
                              value: tx.include,
                              onChanged:
                                  (v) => setState(() => tx.include = v ?? true),
                            ),
                            title: Text(
                              tx.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${DateFormat('MMM d, yyyy').format(tx.date)}'
                              '${tx.category != null ? '  ·  ${tx.category}' : ''}'
                              '${tx.likelyDuplicate ? '  ·  Already imported?' : ''}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_editedTxns.contains(tx))
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.edit_outlined,
                                      size: 14,
                                      color: cs.primary,
                                    ),
                                  ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${isCredit ? '+' : '-'}${_formatAmount(tx.amount, tx.currency)}',
                                      style: TextStyle(
                                        color:
                                            isCredit
                                                ? const Color(0xFF1D9E75)
                                                : cs.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      tx.currency,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            onTap: () => _editTransaction(i),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              )
              : Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 56,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.result.aiConsentDeclined
                            ? 'Nothing was sent'
                            : 'No transactions found',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _emptyMessage(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (widget.result.sentTo != null) ...[
                        const SizedBox(height: 12),
                        _SentToNote(recipient: widget.result.sentTo!),
                      ],
                      if (widget.result.pdfScanned ||
                          widget.result.pdfAiNotReady ||
                          widget.result.aiConsentDeclined) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('Connect AI Provider'),
                        ),
                      ],
                      if (widget.result.tierUsed == ImportTier.manual) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back to Column Mapper'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      bottomNavigationBar:
          hasTransactions
              ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              _importing ||
                                      _likelyDuplicates == null ||
                                      _includeCount == 0
                                  ? null
                                  : _import,
                          icon:
                              _importing
                                  ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onBitcoinOrange,
                                    ),
                                  )
                                  : const Icon(Icons.download_done),
                          label: Text(
                            _progress ??
                                'Import $_includeCount transaction'
                                    '${_includeCount != 1 ? 's' : ''}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              : null,
    );
  }

  /// Why the preview is empty, most specific cause first.
  String _emptyMessage() {
    final r = widget.result;
    final isImage = r.fileType == ImportFileType.image;
    if (r.errorMessage != null) return r.errorMessage!;
    if (r.aiConsentDeclined) {
      return isImage
          ? 'A photo of a statement can only be read by an AI model, and you '
              'chose not to send it. Nothing left your device. Export a CSV '
              'from your bank, or pick an on-device AI provider in Settings → '
              'Servers.'
          : 'This statement needs an AI model to read, and you chose not to '
              'send it. Nothing left your device — try a CSV export, or pick '
              'an on-device AI provider in Settings → Servers.';
    }
    if (r.pdfScanned) {
      return 'This appears to be a scanned PDF with no text layer. Connect an '
          'AI provider with vision support to import scanned documents, or '
          "export as CSV from your bank's website.";
    }
    if (r.pdfAiNotReady) {
      return "Heuristic detection couldn't find enough transactions. Connect "
          'an AI provider for accurate PDF import, or export as CSV from your '
          "bank's website.";
    }
    if (r.isPdfNoAi) {
      return isImage
          ? 'The AI could not extract any transactions from this image. Make '
              'sure your model supports vision (e.g. llava, llama3.2-vision) '
              'and the image clearly shows transaction data.'
          : 'The AI could not extract any transactions from this PDF. Try a '
              'different model or check that the PDF contains readable '
              'transaction data.';
    }
    if (r.tierUsed == ImportTier.manual) {
      return 'No transactions could be extracted with the current column '
          'mapping — go back and check your column assignments.';
    }
    return 'Could not parse this file automatically.';
  }

  /// The AI tiers are named after the provider that actually read the file.
  String _tierLabel(ImportTier tier) => switch (tier) {
    ImportTier.ollama => widget.result.aiLabel ?? 'AI',
    ImportTier.rules => 'Smart Rules',
    ImportTier.manual => 'Saved Mapping',
    ImportTier.pdfHeuristic => 'PDF Heuristics',
    ImportTier.image => '${widget.result.aiLabel ?? 'AI'} (image)',
  };

  String _formatAmount(double amount, String currency) {
    if (currency == 'BTC') return '${amount.toStringAsFixed(8)} BTC';
    if (currency == 'SATS') return '${amount.round()} sats';
    return NumberFormat.currency(symbol: '', decimalDigits: 2).format(amount);
  }
}

/// Says the file was uploaded, and to whom.
class _SentToNote extends StatelessWidget {
  const _SentToNote({required this.recipient});
  final String recipient;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.textSecondary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_upload_outlined,
          size: 14,
          color: context.textSecondary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'This file was sent to $recipient to be read.',
            style: style,
          ),
        ),
      ],
    );
  }
}
