import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' show Value;
import '../../../core/database/database.dart';
import '../../../core/services/transaction_service.dart';
import '../../../core/services/category_service.dart';
import '../../../core/services/wallet_service.dart';
import '../../../core/services/btc_price_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/sat_converter.dart';
import '../../../shared/utils/hash_utils.dart';
import '../../../shared/utils/currency_utils.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../main.dart' as app;

class AddTransactionSheet extends StatefulWidget {
  const AddTransactionSheet({
    super.key,
    required this.transactionService,
    required this.categoryService,
    required this.walletService,
    required this.btcPriceService,
    this.existing,
  });

  final TransactionService transactionService;
  final CategoryService categoryService;
  final WalletService walletService;
  final BtcPriceService btcPriceService;
  /// When non-null, the sheet opens in edit mode pre-populated with this transaction.
  final Transaction? existing;

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isExpense = true;
  bool _isFiatMode = true;
  DateTime _selectedDate = DateTime.now();
  Category? _selectedCategory;
  List<Category> _categories = [];
  bool _saving = false;
  bool _showNotes = false;
  bool _isRecurring = false;
  String _recurringPeriod = 'monthly'; // 'weekly' | 'monthly' | 'yearly'

  double? get _btcPrice => widget.btcPriceService.priceNotifier.value;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    widget.btcPriceService.priceNotifier.addListener(_onPriceChange);

    final tx = widget.existing;
    if (tx != null) {
      _isExpense = tx.amountFiat < 0;
      _isFiatMode = true;
      _amountController.text = tx.amountFiat.abs().toStringAsFixed(2);
      _descriptionController.text = tx.description;
      _notesController.text = tx.notes ?? '';
      _showNotes = tx.notes != null && tx.notes!.isNotEmpty;
      _selectedDate = tx.date;
      if (tx.recurringPeriod != null) {
        _isRecurring = true;
        _recurringPeriod = tx.recurringPeriod!;
      }
    }

    _loadCategories();
  }

  void _onPriceChange() => setState(() {});

  Future<void> _loadCategories() async {
    final categories = await widget.categoryService.getAll();
    if (mounted) {
      setState(() {
        _categories = categories;
        final existing = widget.existing;
        if (existing != null) {
          _selectedCategory =
              categories.where((c) => c.name == existing.category).firstOrNull;
        }
        _selectedCategory ??=
            categories.where((c) => c.name != 'Income').firstOrNull;
      });
    }
  }

  @override
  void dispose() {
    widget.btcPriceService.priceNotifier.removeListener(_onPriceChange);
    _amountController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _conversionLabel {
    final raw = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (raw == null || raw == 0) return '';
    final price = _btcPrice;
    if (price == null || price <= 0) return 'BTC price unavailable';

    if (_isFiatMode) {
      final sats = SatConverter.fiatToSats(raw, price);
      return '≈ ${SatConverter.formatSats(sats)} sats';
    } else {
      final fiat = SatConverter.satsToFiat(raw.round(), price);
      return '≈ \$${fiat.toStringAsFixed(2)}';
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2009, 1, 3), // Bitcoin genesis block
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final rawAmount =
          double.parse(_amountController.text.replaceAll(',', ''));
      final wallet = await widget.walletService.getDefaultManual();
      if (wallet == null) {
        _showError('No manual account found. Please restart the app.');
        return;
      }

      final price = _btcPrice;
      double amountFiat;
      int amountSats;

      if (_isFiatMode) {
        amountFiat = rawAmount;
        amountSats = price != null && price > 0
            ? SatConverter.fiatToSats(rawAmount, price)
            : 0;
      } else {
        amountSats = rawAmount.round();
        amountFiat = price != null && price > 0
            ? SatConverter.satsToFiat(amountSats, price)
            : 0;
      }

      // Apply sign: expenses are negative
      if (_isExpense) {
        amountFiat = -amountFiat.abs();
        amountSats = -amountSats.abs();
      } else {
        amountFiat = amountFiat.abs();
        amountSats = amountSats.abs();
      }

      final period = _isRecurring ? Value<String?>(_recurringPeriod) : const Value<String?>(null);
      final anchor = _isRecurring
          ? Value<DateTime?>(_selectedDate)
          : const Value<DateTime?>(null);

      if (_isEditing) {
        final tx = widget.existing!;
        // Preserve the original anchor date if we're editing a recurring series
        final editAnchor = _isRecurring
            ? Value<DateTime?>(tx.recurringAnchorDate ?? _selectedDate)
            : const Value<DateTime?>(null);
        await widget.transactionService.update(
          TransactionsCompanion(
            id: Value(tx.id),
            date: Value(_selectedDate),
            description: Value(_descriptionController.text.trim()),
            amountSats: Value(amountSats),
            amountFiat: Value(amountFiat),
            category: Value(_selectedCategory?.name),
            notes: Value(_notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim()),
            recurringPeriod: period,
            recurringAnchorDate: editAnchor,
          ),
        );
      } else {
        final dedupHash = HashUtils.transactionDedupHash(
          date: _selectedDate,
          amount: amountFiat,
          description: _descriptionController.text.trim(),
          salt: DateTime.now().microsecondsSinceEpoch.toString(),
        );

        await widget.transactionService.add(
          TransactionsCompanion.insert(
            walletId: wallet.id,
            date: _selectedDate,
            description: _descriptionController.text.trim(),
            amountSats: amountSats,
            amountFiat: amountFiat,
            fiatCurrency: AppConstants.defaultCurrency,
            category: Value(_selectedCategory?.name),
            source: 'manual',
            notes: Value(_notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim()),
            dedupHash: dedupHash,
            recurringPeriod: period,
            recurringAnchorDate: anchor,
          ),
        );
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showError('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
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
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle + title
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (_isEditing) ...[
                    Text(
                      'Edit Transaction',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Expense / Income toggle
                  _TypeToggle(
                    isExpense: _isExpense,
                    onChanged: (v) => setState(() {
                      _isExpense = v;
                      if (!_isExpense) {
                        _selectedCategory = _categories
                            .where((c) => c.name == 'Income')
                            .firstOrNull;
                      } else {
                        _selectedCategory = _categories
                            .where((c) => c.name != 'Income')
                            .firstOrNull;
                      }
                    }),
                  ),
                  const SizedBox(height: 20),

                  // Amount field
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                          style: AppTextStyles.monoLarge.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            hintStyle: AppTextStyles.monoLarge.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            prefixText: _isFiatMode ? '${CurrencyUtils.symbolFor(app.currencyNotifier.value)} ' : '',
                            suffixText: !_isFiatMode ? ' sats' : '',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Enter amount';
                            final n = double.tryParse(v.replaceAll(',', ''));
                            if (n == null || n <= 0) return 'Enter a valid amount';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Fiat / Sats toggle
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: GestureDetector(
                          onTap: () => setState(() => _isFiatMode = !_isFiatMode),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.bitcoinOrange.withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.bitcoinOrange.withAlpha(80),
                              ),
                            ),
                            child: Text(
                              _isFiatMode ? 'USD' : 'SATS',
                              style: AppTextStyles.monoSmall.copyWith(
                                color: AppColors.bitcoinOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Conversion hint
                  if (_conversionLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 2),
                      child: Text(
                        _conversionLabel,
                        style: AppTextStyles.monoSmall.copyWith(
                          color: AppColors.bitcoinOrange,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'e.g. Coffee, Rent, Salary…',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a description' : null,
                  ),
                  const SizedBox(height: 16),

                  // Category chips
                  if (_categories.isNotEmpty) ...[
                    Text(
                      'Category',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _CategoryChips(
                      categories: _categories,
                      selected: _selectedCategory,
                      onSelect: (c) => setState(() => _selectedCategory = c),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Date picker row
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.inputDecorationTheme.fillColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outline,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            DateFormat('EEEE, MMMM d, yyyy')
                                .format(_selectedDate),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Notes toggle
                  GestureDetector(
                    onTap: () => setState(() => _showNotes = !_showNotes),
                    child: Row(
                      children: [
                        Icon(
                          _showNotes
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Add notes',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showNotes) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        hintText: 'Optional',
                      ),
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Repeat toggle
                  GestureDetector(
                    onTap: () => setState(() => _isRecurring = !_isRecurring),
                    child: Row(
                      children: [
                        Icon(
                          _isRecurring
                              ? Icons.repeat_on_outlined
                              : Icons.repeat,
                          size: 16,
                          color: _isRecurring
                              ? AppColors.bitcoinOrange
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Repeat',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _isRecurring
                                ? AppColors.bitcoinOrange
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isRecurring) ...[
                    const SizedBox(height: 10),
                    _PeriodChips(
                      selected: _recurringPeriod,
                      onSelect: (p) => setState(() => _recurringPeriod = p),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Save button
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isEditing ? 'Update Transaction' : 'Save Transaction'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.isExpense, required this.onChanged});

  final bool isExpense;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Chip(
          label: 'Expense',
          selected: isExpense,
          selectedColor: AppColors.danger,
          icon: Icons.arrow_downward,
          onTap: () => onChanged(true),
        )),
        const SizedBox(width: 8),
        Expanded(child: _Chip(
          label: 'Income',
          selected: !isExpense,
          selectedColor: AppColors.success,
          icon: Icons.arrow_upward,
          onTap: () => onChanged(false),
        )),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedColor.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? selectedColor : Theme.of(context).colorScheme.outline,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: selected ? selectedColor : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? selectedColor : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<Category> categories;
  final Category? selected;
  final ValueChanged<Category> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final cat = categories[i];
          final isSelected = selected?.id == cat.id;
          final color = _parseColor(cat.color) ?? AppColors.textSecondary;

          return GestureDetector(
            onTap: () => onSelect(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? color.withAlpha(30) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? color : AppColors.textSecondary.withAlpha(80),
                  width: isSelected ? 1.5 : 0.5,
                ),
              ),
              child: Text(
                cat.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? color : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color? _parseColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return null;
    final value = int.tryParse('FF$clean', radix: 16);
    return value != null ? Color(value) : null;
  }
}

class _PeriodChips extends StatelessWidget {
  const _PeriodChips({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  static const _options = [
    ('weekly', 'Weekly'),
    ('monthly', 'Monthly'),
    ('yearly', 'Yearly'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (value, label) in _options) ...[
          _PeriodChip(
            label: label,
            selected: selected == value,
            onTap: () => onSelect(value),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.bitcoinOrange;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : AppColors.textSecondary.withAlpha(80),
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? color : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
