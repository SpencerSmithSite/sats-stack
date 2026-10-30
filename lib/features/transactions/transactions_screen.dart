import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/database.dart';
import '../../main.dart' as app;
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/btc_price_chip.dart';
import '../../shared/widgets/empty_state.dart';
import 'widgets/add_transaction_sheet.dart';
import 'widgets/manage_wallets_sheet.dart';
import 'widgets/transaction_edit_sheet.dart';
import 'widgets/transaction_list_item.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _searchQuery = '';
  final Set<String> _filterCategories = {};
  final Set<String> _filterSources = {};
  late final TextEditingController _searchCtrl;

  /// Built once. `watchAll()` returns a *new* Drift stream on every call, so
  /// subscribing from inside build() meant every keystroke in the search box
  /// tore down the subscription, re-queried the table and replaced the whole
  /// list with a spinner while the first event came back.
  late final Stream<List<Transaction>> _transactions;

  /// Category name → category, for the colour and icon each row shows.
  /// Every row used to run `categoryService.getAll()` in its own
  /// FutureBuilder: one full table select per visible transaction, repeated
  /// on every rebuild. Watched rather than fetched, so a rename or a colour
  /// change still reaches the list.
  Map<String, Category> _categoriesByName = const {};
  StreamSubscription<List<Category>>? _categorySub;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _transactions = app.transactionService.watchAll();
    _categorySub = app.categoryService.watchAll().listen((cats) {
      if (!mounted) return;
      setState(() => _categoriesByName = {for (final c in cats) c.name: c});
    });
  }

  @override
  void dispose() {
    _categorySub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _filterCategories.isNotEmpty || _filterSources.isNotEmpty;

  List<Transaction> _applyFilters(List<Transaction> all) {
    var result = all;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result =
          result
              .where(
                (t) =>
                    t.description.toLowerCase().contains(q) ||
                    (t.category?.toLowerCase().contains(q) ?? false) ||
                    (t.notes?.toLowerCase().contains(q) ?? false),
              )
              .toList();
    }
    if (_filterCategories.isNotEmpty) {
      result =
          result
              .where((t) => _filterCategories.contains(t.category ?? 'Other'))
              .toList();
    }
    if (_filterSources.isNotEmpty) {
      result = result.where((t) => _filterSources.contains(t.source)).toList();
    }
    return result;
  }

  void _clearFilters() => setState(() {
    _filterCategories.clear();
    _filterSources.clear();
  });

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => AddTransactionSheet(
            transactionService: app.transactionService,
            categoryService: app.categoryService,
            walletService: app.walletService,
            btcPriceService: app.btcPriceService,
          ),
    );
  }

  void _openWallets() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => ManageWalletsSheet(
            xpubService: app.xpubService,
            walletService: app.walletService,
            btcPriceService: app.btcPriceService,
          ),
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _FilterSheet(
            activeCategories: Set.from(_filterCategories),
            activeSources: Set.from(_filterSources),
            onApply:
                (cats, sources) => setState(() {
                  _filterCategories
                    ..clear()
                    ..addAll(cats);
                  _filterSources
                    ..clear()
                    ..addAll(sources);
                }),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Transactions'),
        ),
        // The default spacing, as on every other tab: 0 put the title flush
        // against the screen edge.
        centerTitle: false,
        actions: [
          BtcPriceChip(service: app.btcPriceService),
          const SizedBox(width: 4),
          Badge(
            isLabelVisible: _hasActiveFilters,
            backgroundColor: AppColors.bitcoinOrange,
            child: IconButton(
              icon: const Icon(Icons.filter_list_outlined),
              onPressed: _openFilterSheet,
              tooltip: 'Filter',
              padding: const EdgeInsets.all(8),
              visualDensity: VisualDensity.compact,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: _openWallets,
            tooltip: 'Bitcoin wallets',
            padding: const EdgeInsets.all(8),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () => context.push('/import'),
            tooltip: 'Import',
            padding: const EdgeInsets.all(8),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search transactions…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon:
                    _searchQuery.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                        : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // ── Active filter chips ───────────────────────────────────────
          if (_hasActiveFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final cat in _filterCategories)
                          _ActiveFilterChip(
                            label: cat,
                            onRemove:
                                () => setState(
                                  () => _filterCategories.remove(cat),
                                ),
                          ),
                        for (final src in _filterSources)
                          _ActiveFilterChip(
                            label: _sourceLabel(src),
                            onRemove:
                                () =>
                                    setState(() => _filterSources.remove(src)),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _clearFilters,
                    style: TextButton.styleFrom(
                      foregroundColor: context.textSecondary,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          // ── Transaction list ──────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Transaction>>(
              stream: _transactions,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snapshot.data ?? [];

                if (all.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions yet',
                    subtitle:
                        'Add your first transaction manually or import a bank CSV.',
                    actionLabel: 'Add Transaction',
                    onAction: _openAddSheet,
                  );
                }

                final filtered = _applyFilters(all);

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'No results',
                    subtitle:
                        'Try a different search term or clear the filters.',
                    actionLabel: 'Clear filters',
                    onAction: () {
                      _searchCtrl.clear();
                      setState(() {
                        _searchQuery = '';
                        _clearFilters();
                      });
                    },
                  );
                }

                return _TransactionList(
                  transactions: filtered,
                  categoriesByName: _categoriesByName,
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddSheet,
        backgroundColor: AppColors.bitcoinOrange,
        foregroundColor: AppColors.onBitcoinOrange,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Filter sheet ──────────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.activeCategories,
    required this.activeSources,
    required this.onApply,
  });

  final Set<String> activeCategories;
  final Set<String> activeSources;
  final void Function(Set<String> categories, Set<String> sources) onApply;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Set<String> _categories;
  late final Set<String> _sources;
  List<Category> _allCategories = [];

  static const _allSources = ['manual', 'csv', 'xpub'];

  @override
  void initState() {
    super.initState();
    _categories = Set.from(widget.activeCategories);
    _sources = Set.from(widget.activeSources);
    app.categoryService.getAll().then((cats) {
      if (mounted) setState(() => _allCategories = cats);
    });
  }

  void _apply() {
    widget.onApply(_categories, _sources);
    Navigator.pop(context);
  }

  void _clearAll() => setState(() {
    _categories.clear();
    _sources.clear();
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAny = _categories.isNotEmpty || _sources.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle + header row
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: context.textSecondary.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Text('Filter', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (hasAny)
                TextButton(
                  onPressed: _clearAll,
                  style: TextButton.styleFrom(
                    foregroundColor: context.textSecondary,
                  ),
                  child: const Text('Clear all'),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Source section
          Text(
            'Source',
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.textSecondary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children:
                _allSources
                    .map(
                      (src) => FilterChip(
                        label: Text(_sourceLabel(src)),
                        selected: _sources.contains(src),
                        onSelected:
                            (on) => setState(
                              () =>
                                  on ? _sources.add(src) : _sources.remove(src),
                            ),
                      ),
                    )
                    .toList(),
          ),

          const SizedBox(height: 16),

          // Category section
          Text(
            'Category',
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.textSecondary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children:
                _allCategories
                    .map(
                      (cat) => FilterChip(
                        label: Text(cat.name),
                        selected: _categories.contains(cat.name),
                        onSelected:
                            (on) => setState(
                              () =>
                                  on
                                      ? _categories.add(cat.name)
                                      : _categories.remove(cat.name),
                            ),
                      ),
                    )
                    .toList(),
          ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _apply, child: const Text('Apply')),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _sourceLabel(String source) => switch (source) {
  'manual' => 'Manual',
  'csv' => 'CSV import',
  'xpub' => 'xpub wallet',
  _ => source,
};

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close, size: 14),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ── Transaction list (unchanged logic) ───────────────────────────────────────

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.transactions,
    required this.categoriesByName,
  });

  final List<Transaction> transactions;
  final Map<String, Category> categoriesByName;

  @override
  Widget build(BuildContext context) {
    final groups = <DateTime, List<Transaction>>{};
    for (final tx in transactions) {
      final date = DateTime(tx.date.year, tx.date.month, tx.date.day);
      groups.putIfAbsent(date, () => []).add(tx);
    }
    final sortedDates = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: sortedDates.length,
      itemBuilder: (context, i) {
        final date = sortedDates[i];
        final dayTxs = groups[date]!;
        return _DateGroup(
          date: date,
          transactions: dayTxs,
          categoriesByName: categoriesByName,
        );
      },
    );
  }
}

class _DateGroup extends StatelessWidget {
  const _DateGroup({
    required this.date,
    required this.transactions,
    required this.categoriesByName,
  });

  final DateTime date;
  final List<Transaction> transactions;
  final Map<String, Category> categoriesByName;

  String _dateLabel() {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day) {
      return 'Today';
    }
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    return DateFormat('EEEE, MMMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            _dateLabel(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: context.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              for (int j = 0; j < transactions.length; j++) ...[
                _TransactionRow(
                  transaction: transactions[j],
                  category: categoriesByName[transactions[j].category],
                ),
                if (j < transactions.length - 1)
                  const Divider(indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction, this.category});

  final Transaction transaction;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    return TransactionListItem(
      transaction: transaction,
      category: category,
      onTap: () => _openEditSheet(context, transaction),
      onLongPress: () => _confirmDelete(context),
    );
  }

  void _openEditSheet(BuildContext context, Transaction tx) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TransactionEditSheet.forExisting(tx),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      // Pop with the dialog's own context: the dialog is on the root
      // navigator, and `context` is this row's, inside the tab's navigator —
      // popping that removed the tab's only page and blanked the app.
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete transaction?'),
            content: Text(
              'Remove "${transaction.description.isEmpty ? 'this transaction' : transaction.description}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  app.transactionService.deleteById(transaction.id);
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }
}
