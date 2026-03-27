import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/import_service.dart';
import '../../main.dart' as app;
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
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _txns = List.of(widget.result.transactions);
  }

  int get _includeCount => _txns.where((t) => t.include).length;

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final summary = await app.importService.saveTransactions(
        transactions: _txns,
        sourceId: widget.sourceId,
        sourceName: widget.sourceName,
        btcPrice: app.btcPriceService.priceNotifier.value,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ImportSummaryScreen(summary: summary),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _editTransaction(int index) {
    final tx = _txns[index];
    final amountCtrl =
        TextEditingController(text: tx.amount.toStringAsFixed(2));
    final descCtrl = TextEditingController(text: tx.description);
    String direction = tx.direction;
    DateTime date = tx.date;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Edit Transaction',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'debit', label: Text('Debit')),
                    ButtonSegment(value: 'credit', label: Text('Credit')),
                  ],
                  selected: {direction},
                  onSelectionChanged: (s) =>
                      setLocal(() => direction = s.first),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _txns[index]
                              ..amount = double.tryParse(amountCtrl.text) ??
                                  tx.amount
                              ..description = descCtrl.text.trim()
                              ..direction = direction
                              ..date = date;
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
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
      body: hasTransactions
          ? Column(
              children: [
                // Header card
                Container(
                  width: double.infinity,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.sourceName,
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        '${_txns.length} transaction${_txns.length != 1 ? 's' : ''} found'
                        '${start != null ? '  ·  ${DateFormat('MMM d, yyyy').format(start)} – ${DateFormat('MMM d, yyyy').format(end!)}' : ''}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      if (widget.result.tierUsed != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Parsed via ${_tierLabel(widget.result.tierUsed!)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.primary),
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
                            onChanged: (v) =>
                                setState(() => tx.include = v ?? true),
                          ),
                          title: Text(
                            tx.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${DateFormat('MMM d, yyyy').format(tx.date)}'
                            '${tx.category != null ? '  ·  ${tx.category}' : ''}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isCredit ? '+' : '-'}${_formatAmount(tx.amount, tx.currency)}',
                                style: TextStyle(
                                  color: isCredit
                                      ? const Color(0xFF1D9E75)
                                      : cs.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                tx.currency,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
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
                    Icon(Icons.search_off_rounded,
                        size: 56, color: cs.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text('No transactions found',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      widget.result.isPdfNoAi
                          ? 'PDF import requires Ollama to be connected and a model selected. Connect Ollama in Settings → Servers.'
                          : widget.result.tierUsed == ImportTier.manual
                              ? 'No transactions could be extracted with the current column mapping — go back and check your column assignments.'
                              : 'Could not parse this file automatically.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
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
      bottomNavigationBar: hasTransactions
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
                            _importing || _includeCount == 0 ? null : _import,
                        icon: _importing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Icon(Icons.download_done),
                        label: Text('Import $_includeCount transaction'
                            '${_includeCount != 1 ? 's' : ''}'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  String _tierLabel(ImportTier tier) => switch (tier) {
        ImportTier.ollama => 'Ollama AI',
        ImportTier.rules => 'Smart Rules',
        ImportTier.manual => 'Saved Mapping',
        ImportTier.pdfExtracted => 'PDF + AI',
      };

  String _formatAmount(double amount, String currency) {
    if (currency == 'BTC') return '${amount.toStringAsFixed(8)} BTC';
    if (currency == 'SATS') return '${amount.round()} sats';
    return NumberFormat.currency(symbol: '', decimalDigits: 2)
        .format(amount);
  }
}
