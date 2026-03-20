import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/database/database.dart';
import '../../../core/models/budget_progress.dart';
import '../../../core/services/budget_service.dart';
import '../../../core/services/category_service.dart';
import '../../../main.dart' as app;
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/currency_utils.dart';

class SetBudgetSheet extends StatefulWidget {
  const SetBudgetSheet({
    super.key,
    required this.budgetService,
    required this.categoryService,
    this.existing,
  });

  final BudgetService budgetService;
  final CategoryService categoryService;
  /// Pre-populate for editing an existing budget.
  final BudgetProgress? existing;

  @override
  State<SetBudgetSheet> createState() => _SetBudgetSheetState();
}

class _SetBudgetSheetState extends State<SetBudgetSheet> {
  final _amountController = TextEditingController();

  List<Category> _categories = [];
  List<Budget> _existingBudgets = [];
  Category? _selectedCategory;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _selectedCategory = widget.existing!.category;
      _amountController.text =
          widget.existing!.budget.amountFiat.toStringAsFixed(2);
    }
    _load();
  }

  Future<void> _load() async {
    final cats = await widget.categoryService.getAll();
    final budgets = await widget.budgetService.getAll();
    if (!mounted) return;
    setState(() {
      _categories = cats.where((c) => c.name != 'Income').toList();
      _existingBudgets = budgets;
      _selectedCategory ??= _unbudgetedCategories.firstOrNull ?? _categories.firstOrNull;
    });
  }

  List<Category> get _unbudgetedCategories {
    final budgetedIds = _existingBudgets.map((b) => b.categoryId).toSet();
    return _categories.where((c) => !budgetedIds.contains(c.id)).toList();
  }

  Future<void> _save() async {
    final cat = _selectedCategory;
    if (cat == null) return;
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.budgetService.upsert(
        categoryId: cat.id,
        amountFiat: amount,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _saving = false; _error = 'Error: $e'; });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  isEditing ? 'Edit Budget' : 'Set Monthly Budget',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),

                // Category selector
                if (!isEditing) ...[
                  Text(
                    'Category',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  _CategoryGrid(
                    categories: _categories,
                    selected: _selectedCategory,
                    onSelect: (c) => setState(() => _selectedCategory = c),
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  _SelectedCategoryRow(category: widget.existing!.category),
                  const SizedBox(height: 20),
                ],

                // Amount field
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  style: AppTextStyles.monoLarge.copyWith(color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Monthly budget',
                    prefixText: '${CurrencyUtils.symbolFor(app.currencyNotifier.value)} ',
                    hintText: '500.00',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
                const SizedBox(height: 24),

                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                  child: _saving
                      ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Budget'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedCategoryRow extends StatelessWidget {
  const _SelectedCategoryRow({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(category.color) ?? AppColors.textSecondary;
    return Row(
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          category.name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Color? _parseColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return null;
    final value = int.tryParse('FF$clean', radix: 16);
    return value != null ? Color(value) : null;
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories, required this.selected, required this.onSelect});

  final List<Category> categories;
  final Category? selected;
  final ValueChanged<Category> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final cat in categories)
          _CategoryChip(
            category: cat,
            isSelected: selected?.id == cat.id,
            onTap: () => onSelect(cat),
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.isSelected, required this.onTap});

  final Category category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(category.color) ?? AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : AppColors.textSecondary.withAlpha(80),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              category.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
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
