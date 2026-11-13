import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/database.dart';
import '../../main.dart' as app;
import '../../shared/theme/app_colors.dart';
import '../../shared/utils/date_range.dart';
import '../../shared/widgets/btc_price_chip.dart';
import '../../shared/widgets/empty_state.dart';
import 'transaction_filter.dart';
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

  /// Half-open, like every other range in the app, so the whole of its last
  /// day is in it. Tested against each row's stored date the way months are.
  DateRange? _filterDates;
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

  /// Search waits for a pause in typing, and the list is worked out again
  /// only when the rows, the search or the filters change. Every keystroke
  /// filtered every transaction and regrouped them by day, which lagged on a
  /// long history (audit U-17).
  Timer? _searchPause;
  static const _searchPauseLength = Duration(milliseconds: 250);
  ({
    String query,
    Set<String> categories,
    Set<String> sources,
    DateRange? dates,
    _Days days,
  })?
  _shown;

  /// The rows' searchable text, prepared once per list of rows rather than
  /// on every search.
  TransactionSearch? _search;

  /// [all] filtered and grouped by day, newest first: the exact matches, and
  /// separately the close ones.
  _Days _days(List<Transaction> all) {
    var search = _search;
    final shown = _shown;
    final sameRows = search != null && identical(search.rows, all);
    if (sameRows &&
        shown != null &&
        shown.query == _searchQuery &&
        setEquals(shown.categories, _filterCategories) &&
        setEquals(shown.sources, _filterSources) &&
        shown.dates == _filterDates) {
      return shown.days;
    }
    if (!sameRows) search = _search = TransactionSearch(all);
    final results = search.search(_searchQuery, include: _passesFilters);
    final days = (
      exact: _groupByDay(results.exact),
      close: _groupByDay(results.close),
    );
    _shown = (
      query: _searchQuery,
      categories: {..._filterCategories},
      sources: {..._filterSources},
      dates: _filterDates,
      days: days,
    );
    return days;
  }

  static List<(DateTime, List<Transaction>)> _groupByDay(
    List<Transaction> rows,
  ) {
    final groups = <DateTime, List<Transaction>>{};
    for (final tx in rows) {
      final date = DateTime(tx.date.year, tx.date.month, tx.date.day);
      groups.putIfAbsent(date, () => []).add(tx);
    }
    return [
      for (final date in groups.keys.toList()..sort((a, b) => b.compareTo(a)))
        (date, groups[date]!),
    ];
  }

  void _onSearchChanged(String text) {
    _searchPause?.cancel();
    _searchPause = Timer(_searchPauseLength, () {
      if (mounted) setState(() => _searchQuery = text);
    });
  }

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
    _searchPause?.cancel();
    _categorySub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// How many filters are on, for the badge on the filter button.
  int get _activeFilterCount =>
      _filterCategories.length +
      _filterSources.length +
      (_filterDates == null ? 0 : 1);

  bool get _hasActiveFilters => _activeFilterCount > 0;

  bool _passesFilters(Transaction t) =>
      (_filterCategories.isEmpty ||
          _filterCategories.contains(t.category ?? 'Other')) &&
      (_filterSources.isEmpty || _filterSources.contains(t.source)) &&
      (_filterDates?.contains(t.date) ?? true);

  void _clearFilters() => setState(() {
    _filterCategories.clear();
    _filterSources.clear();
    _filterDates = null;
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
            activeDates: _filterDates,
            onApply:
                (cats, sources, dates) => setState(() {
                  _filterCategories
                    ..clear()
                    ..addAll(cats);
                  _filterSources
                    ..clear()
                    ..addAll(sources);
                  _filterDates = dates;
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
            label: Text('$_activeFilterCount'),
            backgroundColor: AppColors.bitcoinOrange,
            textColor: AppColors.onBitcoinOrange,
            child: IconButton(
              icon: const Icon(Icons.filter_list_outlined),
              onPressed: _openFilterSheet,
              tooltip: 'Filter',
              padding: const EdgeInsets.all(8),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: _openWallets,
            tooltip: 'Bitcoin wallets',
            padding: const EdgeInsets.all(8),
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () => context.push('/import'),
            tooltip: 'Import',
            padding: const EdgeInsets.all(8),
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
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchPause?.cancel();
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
              onChanged: _onSearchChanged,
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
                        if (_filterDates case final dates?)
                          _ActiveFilterChip(
                            label: dateRangeLabel(dates, DateTime.now()),
                            onRemove: () => setState(() => _filterDates = null),
                          ),
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
                        'Add your first transaction manually, or import a '
                        'statement (CSV, PDF or a photo).',
                    actionLabel: 'Add Transaction',
                    onAction: _openAddSheet,
                  );
                }

                final days = _days(all);

                if (days.exact.isEmpty && days.close.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'No results',
                    subtitle:
                        'Try a different search term or clear the filters.',
                    actionLabel: 'Clear filters',
                    onAction: () {
                      _searchPause?.cancel();
                      _searchCtrl.clear();
                      setState(() {
                        _searchQuery = '';
                        _clearFilters();
                      });
                    },
                  );
                }

                return _TransactionList(
                  days: days.exact,
                  closeDays: days.close,
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
    required this.activeDates,
    required this.onApply,
  });

  final Set<String> activeCategories;
  final Set<String> activeSources;
  final DateRange? activeDates;
  final void Function(
    Set<String> categories,
    Set<String> sources,
    DateRange? dates,
  )
  onApply;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Set<String> _categories;
  late final Set<String> _sources;
  DateRange? _dates;
  List<Category> _allCategories = [];

  static const _allSources = ['manual', 'csv', 'xpub'];

  @override
  void initState() {
    super.initState();
    _categories = Set.from(widget.activeCategories);
    _sources = Set.from(widget.activeSources);
    _dates = widget.activeDates;
    app.categoryService.getAll().then((cats) {
      if (mounted) setState(() => _allCategories = cats);
    });
  }

  void _apply() {
    widget.onApply(_categories, _sources, _dates);
    Navigator.pop(context);
  }

  void _clearAll() => setState(() {
    _categories.clear();
    _sources.clear();
    _dates = null;
  });

  Future<void> _pickDates() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = _dates;
    // Opens on the range already chosen, preset or not, so it can be
    // adjusted rather than picked again from nothing.
    final initial =
        current == null
            ? null
            : DateTimeRange(start: current.start, end: current.lastDay);
    // Imported rows can predate Bitcoin, and a bank can date one ahead; the
    // picker asserts if the initial range is outside its bounds (audit U-11).
    final first = DateTime(1970);
    final last = DateTime(today.year + 1, 12, 31);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initial,
      firstDate:
          initial != null && initial.start.isBefore(first)
              ? initial.start
              : first,
      lastDate:
          initial != null && initial.end.isAfter(last) ? initial.end : last,
      currentDate: today,
      helpText: 'Show transactions from',
      saveText: 'Done',
      confirmText: 'Done',
    );
    if (picked == null || !mounted) return;
    // The picker's end is the last day itself, at midnight: the range runs
    // to the start of the day after it, so that day is included in full.
    setState(() => _dates = DateRange.days(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAny =
        _categories.isNotEmpty || _sources.isNotEmpty || _dates != null;
    final today = DateTime.now();
    final dates = _dates;
    final preset = dates == null ? null : DatePreset.of(dates, today);
    final isCustom = dates != null && preset == null;

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
      // Scrolls: with many rows or a large text size, the bottom rows
      // and the button were out of reach (audit U-12).
      child: SingleChildScrollView(
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

            // Date section
            Text(
              'Date',
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.textSecondary,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // One range at a time: choosing a preset replaces the last
                // choice, and choosing it again turns it off.
                for (final p in DatePreset.values)
                  FilterChip(
                    label: Text(p.label),
                    selected: preset == p,
                    onSelected:
                        (on) => setState(
                          () => _dates = on ? p.rangeOn(today) : null,
                        ),
                  ),
                FilterChip(
                  avatar: isCustom ? null : const Icon(Icons.date_range),
                  label: Text(
                    isCustom ? dateRangeLabel(dates, today) : 'Custom…',
                  ),
                  selected: isCustom,
                  tooltip: 'Choose dates',
                  onSelected: (_) => _pickDates(),
                ),
              ],
            ),

            const SizedBox(height: 16),

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
                                    on
                                        ? _sources.add(src)
                                        : _sources.remove(src),
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
              child: FilledButton(
                onPressed: _apply,
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ── Transaction list (unchanged logic) ───────────────────────────────────────

/// Each day with its transactions, newest first: the rows that match the
/// search as typed, and those found only by tolerating a typo.
typedef _Days =
    ({
      List<(DateTime, List<Transaction>)> exact,
      List<(DateTime, List<Transaction>)> close,
    });

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.days,
    required this.closeDays,
    required this.categoriesByName,
  });

  /// Each day with its transactions, newest first.
  final List<(DateTime, List<Transaction>)> days;

  /// The same for close matches, after every exact one and under a heading
  /// of their own: mixed in by date, a near miss could sit above the row the
  /// user typed exactly.
  final List<(DateTime, List<Transaction>)> closeDays;
  final Map<String, Category> categoriesByName;

  @override
  Widget build(BuildContext context) {
    final hasClose = closeDays.isNotEmpty;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: days.length + (hasClose ? closeDays.length + 1 : 0),
      itemBuilder: (context, i) {
        if (i == days.length) return const _CloseMatchesHeading();
        final (date, dayTxs) =
            i < days.length ? days[i] : closeDays[i - days.length - 1];
        return _DateGroup(
          date: date,
          transactions: dayTxs,
          categoriesByName: categoriesByName,
        );
      },
    );
  }
}

class _CloseMatchesHeading extends StatelessWidget {
  const _CloseMatchesHeading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Row(
        children: [
          Icon(Icons.manage_search, size: 18, color: context.textSecondary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Close matches',
              style: theme.textTheme.titleSmall?.copyWith(
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      ),
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
                onPressed: () async {
                  Navigator.pop(ctx);
                  // Awaited, and its failure shown: it was neither, so a
                  // delete that failed left the row in place with no word
                  // (audit U-6).
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await app.transactionService.deleteById(transaction.id);
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Could not delete: $e')),
                    );
                  }
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }
}
