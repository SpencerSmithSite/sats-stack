import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/database/database.dart';
import '../../../core/services/import_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../main.dart' as app;

/// A bottom sheet for editing a transaction.
///
/// Two factory constructors:
///   - [TransactionEditSheet.forParsed] — edits a [ParsedTransaction] in-place
///     before import confirmation.  Calls [onSaved] after the user taps Save.
///   - [TransactionEditSheet.forExisting] — edits an already-imported
///     [Transaction] row and persists the change to the database.
class TransactionEditSheet extends StatefulWidget {
  const TransactionEditSheet._({
    super.key,
    this.parsedTx,
    this.existingTx,
    this.onSaved,
  });

  factory TransactionEditSheet.forParsed(
    ParsedTransaction tx, {
    VoidCallback? onSaved,
    Key? key,
  }) =>
      TransactionEditSheet._(key: key, parsedTx: tx, onSaved: onSaved);

  factory TransactionEditSheet.forExisting(
    Transaction tx, {
    Key? key,
  }) =>
      TransactionEditSheet._(key: key, existingTx: tx);

  final ParsedTransaction? parsedTx;
  final Transaction? existingTx;
  final VoidCallback? onSaved;

  @override
  State<TransactionEditSheet> createState() => _TransactionEditSheetState();
}

class _TransactionEditSheetState extends State<TransactionEditSheet> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _customCatCtrl;

  late String _direction; // 'debit' | 'credit'
  late DateTime _date;
  String? _selectedCategory;
  bool _showCustomCat = false;
  bool _saving = false;

  List<Category> _categories = [];

  bool get _isParsed => widget.parsedTx != null;

  @override
  void initState() {
    super.initState();

    if (_isParsed) {
      final tx = widget.parsedTx!;
      _descCtrl = TextEditingController(text: tx.description);
      _amountCtrl = TextEditingController(text: tx.amount.toStringAsFixed(2));
      _direction = tx.direction;
      _date = tx.date;
      _selectedCategory = tx.category;
    } else {
      final tx = widget.existingTx!;
      _descCtrl = TextEditingController(text: tx.description);
      _amountCtrl =
          TextEditingController(text: tx.amountFiat.abs().toStringAsFixed(2));
      _direction = tx.amountFiat >= 0 ? 'credit' : 'debit';
      _date = tx.date;
      _selectedCategory = tx.category;
    }

    _customCatCtrl = TextEditingController();
    _loadCategories();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _customCatCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final cats = await app.categoryService.getAll();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      // Ensure current category is valid; if not found leave as-is (custom)
      final match = cats.where((c) => c.name == _selectedCategory).firstOrNull;
      if (match == null && _selectedCategory != null) {
        _showCustomCat = true;
        _customCatCtrl.text = _selectedCategory!;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2009, 1, 3),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final desc = _descCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount < 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    final category = _showCustomCat
        ? (_customCatCtrl.text.trim().isEmpty ? null : _customCatCtrl.text.trim())
        : _selectedCategory;

    setState(() => _saving = true);
    try {
      if (_isParsed) {
        final tx = widget.parsedTx!;
        tx.description = desc.isEmpty ? tx.description : desc;
        tx.amount = amount;
        tx.direction = _direction;
        tx.date = _date;
        tx.category = category;
        Navigator.pop(context);
        widget.onSaved?.call();
      } else {
        final tx = widget.existingTx!;
        final signedFiat = _direction == 'credit' ? amount : -amount;
        // Recalculate sats proportionally if we have a BTC price
        final price = app.btcPriceService.priceNotifier.value;
        final int newSats;
        if (tx.isBitcoin) {
          newSats = _direction == 'credit'
              ? (amount * 100000000).round()
              : -(amount * 100000000).round();
        } else if (price != null && price > 0) {
          newSats = (signedFiat / price * 100000000).round();
        } else {
          // Keep existing sats if no price available
          newSats = tx.amountSats;
        }

        await app.transactionService.update(
          TransactionsCompanion(
            id: Value(tx.id),
            walletId: Value(tx.walletId),
            date: Value(_date),
            description: Value(desc.isEmpty ? tx.description : desc),
            amountFiat: Value(signedFiat),
            amountSats: Value(newSats),
            fiatCurrency: Value(tx.fiatCurrency),
            category: Value(category),
            source: Value(tx.source),
            isBitcoin: Value(tx.isBitcoin),
            notes: Value(tx.notes),
            dedupHash: Value(tx.dedupHash),
            recurringPeriod: Value(tx.recurringPeriod),
            recurringAnchorDate: Value(tx.recurringAnchorDate),
          ),
        );

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaction updated')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await app.transactionService.deleteById(widget.existingTx!.id);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction deleted')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              children: [
                Text('Edit Transaction', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (!_isParsed)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: AppColors.danger),
                    onPressed: _delete,
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Description
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),

            // Amount
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Direction
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'debit',
                    label: Text('Debit'),
                    icon: Icon(Icons.arrow_upward, size: 16)),
                ButtonSegment(
                    value: 'credit',
                    label: Text('Credit'),
                    icon: Icon(Icons.arrow_downward, size: 16)),
              ],
              selected: {_direction},
              onSelectionChanged: (s) =>
                  setState(() => _direction = s.first),
            ),
            const SizedBox(height: 12),

            // Date
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(DateFormat('MMM d, yyyy').format(_date)),
              ),
            ),
            const SizedBox(height: 12),

            // Category
            if (_categories.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: _showCustomCat
                    ? '__custom__'
                    : (_categories
                            .any((c) => c.name == _selectedCategory)
                        ? _selectedCategory
                        : null),
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  ..._categories.map((c) => DropdownMenuItem(
                        value: c.name,
                        child: Text(c.name),
                      )),
                  const DropdownMenuItem(
                    value: '__custom__',
                    child: Text('Custom…'),
                  ),
                ],
                onChanged: (val) {
                  if (val == '__custom__') {
                    setState(() {
                      _showCustomCat = true;
                      _selectedCategory = null;
                    });
                  } else {
                    setState(() {
                      _showCustomCat = false;
                      _selectedCategory = val;
                    });
                  }
                },
              ),
              if (_showCustomCat) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customCatCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Custom category',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Medical, Travel',
                  ),
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                ),
              ],
              const SizedBox(height: 20),
            ],

            // Save button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
