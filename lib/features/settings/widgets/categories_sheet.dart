import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../core/services/category_service.dart';
import '../../../shared/theme/app_colors.dart';

// ── Public entry point ─────────────────────────────────────────────────────────

class CategoriesSheet extends StatelessWidget {
  const CategoriesSheet({super.key, required this.categoryService});

  final CategoryService categoryService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
                  const Icon(Icons.category_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Categories',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _CategoryList(categoryService: categoryService),
          ],
        ),
      ),
    );
  }
}

// ── Category list ──────────────────────────────────────────────────────────────

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.categoryService});

  final CategoryService categoryService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Category>>(
      stream: categoryService.watchAll(),
      builder: (context, snapshot) {
        final categories = snapshot.data ?? [];
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: categories.length + 1, // +1 for Add button
            itemBuilder: (context, index) {
              if (index == categories.length) {
                return _AddCategoryTile(categoryService: categoryService);
              }
              final cat = categories[index];
              return _CategoryTile(
                category: cat,
                categoryService: categoryService,
              );
            },
          ),
        );
      },
    );
  }
}

// ── Single category tile ───────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.categoryService,
  });

  final Category category;
  final CategoryService categoryService;

  Color _parseColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  IconData _iconData(String name) => _kIconMap[name] ?? Icons.circle;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(category.color);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(_iconData(category.icon), size: 18, color: color),
      ),
      title: Text(category.name),
      subtitle: category.isSystem
          ? Text(
              'System',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Edit — available for all categories
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: AppColors.textSecondary,
            onPressed: () => _openEdit(context),
          ),
          // Delete — custom categories only
          if (!category.isSystem)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: AppColors.danger,
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
      onTap: () => _openEdit(context),
    );
  }

  void _openEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditCategorySheet(
        categoryService: categoryService,
        existing: category,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final counts = await categoryService.usageCounts(category.id, category.name);
    if (!context.mounted) return;

    if (counts.transactions > 0 || counts.budgets > 0) {
      final parts = <String>[];
      if (counts.transactions > 0) {
        parts.add('${counts.transactions} transaction${counts.transactions == 1 ? '' : 's'}');
      }
      if (counts.budgets > 0) {
        parts.add('${counts.budgets} budget${counts.budgets == 1 ? '' : 's'}');
      }
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot delete'),
          content: Text(
            '"${category.name}" is used by ${parts.join(' and ')}. '
            'Reassign or delete those first.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Delete "${category.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await categoryService.deleteCategory(category.id, category.name);
    }
  }
}

// ── Add category tile ──────────────────────────────────────────────────────────

class _AddCategoryTile extends StatelessWidget {
  const _AddCategoryTile({required this.categoryService});

  final CategoryService categoryService;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: OutlinedButton.icon(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _EditCategorySheet(categoryService: categoryService),
        ),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add category'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 44),
        ),
      ),
    );
  }
}

// ── Add / Edit sheet ───────────────────────────────────────────────────────────

class _EditCategorySheet extends StatefulWidget {
  const _EditCategorySheet({
    required this.categoryService,
    this.existing,
  });

  final CategoryService categoryService;
  final Category? existing;

  @override
  State<_EditCategorySheet> createState() => _EditCategorySheetState();
}

class _EditCategorySheetState extends State<_EditCategorySheet> {
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _selectedColor = '#F7931A';
  String _selectedIcon = 'more_horiz';
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final cat = widget.existing;
    if (cat != null) {
      _nameCtrl.text = cat.name;
      _selectedColor = cat.color;
      _selectedIcon = cat.icon;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await widget.categoryService.updateCategory(
          id: widget.existing!.id,
          name: _nameCtrl.text.trim(),
          color: _selectedColor,
          icon: _selectedIcon,
        );
      } else {
        await widget.categoryService.createCategory(
          name: _nameCtrl.text.trim(),
          color: _selectedColor,
          icon: _selectedIcon,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  Text(
                    _isEditing ? 'Edit Category' : 'New Category',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),

                  // Name
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name'),
                    textCapitalization: TextCapitalization.words,
                    autofocus: !_isEditing,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 20),

                  // Color picker
                  Text(
                    'Colour',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _kColorOptions.map((hex) {
                      final color = Color(
                          int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
                      final selected = _selectedColor == hex;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = hex),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: selected
                                ? [BoxShadow(color: color.withAlpha(120), blurRadius: 6)]
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Icon picker
                  Text(
                    'Icon',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  _IconGrid(
                    selectedIcon: _selectedIcon,
                    selectedColor: _selectedColor,
                    onSelect: (icon) => setState(() => _selectedIcon = icon),
                  ),
                  const SizedBox(height: 24),

                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48)),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isEditing ? 'Update' : 'Create'),
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

// ── Icon grid ──────────────────────────────────────────────────────────────────

class _IconGrid extends StatelessWidget {
  const _IconGrid({
    required this.selectedIcon,
    required this.selectedColor,
    required this.onSelect,
  });

  final String selectedIcon;
  final String selectedColor;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final activeColor = Color(
      int.parse('FF${selectedColor.replaceFirst('#', '')}', radix: 16),
    );
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _kIconOptions.length,
      itemBuilder: (context, index) {
        final (key, iconData) = _kIconOptions[index];
        final selected = selectedIcon == key;
        return GestureDetector(
          onTap: () => onSelect(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: selected ? activeColor.withAlpha(30) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? activeColor
                    : Theme.of(context).colorScheme.outline.withAlpha(80),
                width: selected ? 1.5 : 0.5,
              ),
            ),
            child: Icon(
              iconData,
              size: 18,
              color: selected ? activeColor : AppColors.textSecondary,
            ),
          ),
        );
      },
    );
  }
}

// ── Curated data ───────────────────────────────────────────────────────────────

const _kColorOptions = [
  '#F7931A', // Bitcoin orange
  '#E24B4A', // Red
  '#1D9E75', // Green
  '#6AB0E8', // Blue
  '#9B59B6', // Purple
  '#1ABC9C', // Teal
  '#F39C12', // Amber
  '#E91E8C', // Pink
  '#3F51B5', // Indigo
  '#888780', // Grey
];

const _kIconOptions = <(String, IconData)>[
  ('restaurant', Icons.restaurant),
  ('coffee', Icons.coffee),
  ('directions_car', Icons.directions_car),
  ('local_gas_station', Icons.local_gas_station),
  ('flight', Icons.flight),
  ('home', Icons.home),
  ('bed', Icons.bed),
  ('shopping_bag', Icons.shopping_bag),
  ('shopping_cart', Icons.shopping_cart),
  ('subscriptions', Icons.subscriptions),
  ('movie', Icons.movie),
  ('sports_esports', Icons.sports_esports),
  ('fitness_center', Icons.fitness_center),
  ('local_hospital', Icons.local_hospital),
  ('school', Icons.school),
  ('work', Icons.work),
  ('computer', Icons.computer),
  ('phone_android', Icons.phone_android),
  ('currency_bitcoin', Icons.currency_bitcoin),
  ('payments', Icons.payments),
  ('savings', Icons.savings),
  ('attach_money', Icons.attach_money),
  ('pets', Icons.pets),
  ('child_care', Icons.child_care),
  ('park', Icons.park),
  ('celebration', Icons.celebration),
  ('card_giftcard', Icons.card_giftcard),
  ('more_horiz', Icons.more_horiz),
];

// Icon name → IconData lookup used by the tile renderer
const Map<String, IconData> _kIconMap = {
  'restaurant': Icons.restaurant,
  'coffee': Icons.coffee,
  'directions_car': Icons.directions_car,
  'local_gas_station': Icons.local_gas_station,
  'flight': Icons.flight,
  'home': Icons.home,
  'bed': Icons.bed,
  'shopping_bag': Icons.shopping_bag,
  'shopping_cart': Icons.shopping_cart,
  'subscriptions': Icons.subscriptions,
  'movie': Icons.movie,
  'sports_esports': Icons.sports_esports,
  'fitness_center': Icons.fitness_center,
  'local_hospital': Icons.local_hospital,
  'school': Icons.school,
  'work': Icons.work,
  'computer': Icons.computer,
  'phone_android': Icons.phone_android,
  'currency_bitcoin': Icons.currency_bitcoin,
  'payments': Icons.payments,
  'savings': Icons.savings,
  'attach_money': Icons.attach_money,
  'pets': Icons.pets,
  'child_care': Icons.child_care,
  'park': Icons.park,
  'celebration': Icons.celebration,
  'card_giftcard': Icons.card_giftcard,
  'more_horiz': Icons.more_horiz,
};
