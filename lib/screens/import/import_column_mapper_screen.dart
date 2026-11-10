import 'package:flutter/material.dart';

import '../../core/services/import_service.dart';
import '../../main.dart' as app;
import '../../shared/theme/app_colors.dart';
import 'import_preview_screen.dart';

class ImportColumnMapperScreen extends StatefulWidget {
  const ImportColumnMapperScreen({
    super.key,
    required this.result,
    required this.sourceId,
    required this.sourceName,
  });

  final ImportResult result;
  final int sourceId;
  final String sourceName;

  @override
  State<ImportColumnMapperScreen> createState() =>
      _ImportColumnMapperScreenState();
}

class _ImportColumnMapperScreenState extends State<ImportColumnMapperScreen> {
  late List<String> _headers;
  late List<List<String>> _previewRows;
  late ColumnMapping _mapping;
  bool _saveMapping = true;
  bool _parsing = false;

  static const _dateFormats = [
    'MM/DD/YYYY',
    'MM/DD/YY',
    'DD/MM/YYYY',
    'DD/MM/YY',
    'YYYY-MM-DD',
    'MM-DD-YYYY',
    'DD MMM YYYY',
    'MMM DD YYYY',
  ];

  static const _assignOptions = [
    ('skip', 'Skip'),
    ('date', 'Date'),
    ('amount', 'Amount (signed)'),
    ('debit', 'Debit'),
    ('credit', 'Credit'),
    ('description', 'Description'),
  ];

  // Current assignment for each column index
  late List<String> _assignments;

  @override
  void initState() {
    super.initState();
    _headers = widget.result.csvHeaders ?? [];
    final rows = widget.result.csvRows ?? [];
    // Skip header row; take up to 5 preview rows
    _previewRows =
        rows.length > 1 ? rows.sublist(1, rows.length.clamp(1, 6)) : [];
    _mapping = ColumnMapping();
    _assignments = List.filled(_headers.length, 'skip');
  }

  // Inspects the column's dates and auto-selects the date format.
  // Must be called inside setState (mutates _mapping.dateFormat directly).
  void _detectDateFormat(int colIndex) {
    _mapping.dateFormat =
        guessDateFormat([
          for (final r in (widget.result.csvRows ?? const []).skip(1))
            if (colIndex < r.length) r[colIndex],
        ]) ??
        _mapping.dateFormat;
  }

  void _onAssign(int colIndex, String assignment) {
    setState(() {
      // Clear any previous column with this assignment (except 'skip')
      if (assignment != 'skip') {
        for (int i = 0; i < _assignments.length; i++) {
          if (_assignments[i] == assignment) _assignments[i] = 'skip';
        }
      }
      _assignments[colIndex] = assignment;
      _rebuildMapping();
      if (assignment == 'date') _detectDateFormat(colIndex);
    });
  }

  void _rebuildMapping() {
    _mapping = ColumnMapping(dateFormat: _mapping.dateFormat);
    for (int i = 0; i < _assignments.length; i++) {
      switch (_assignments[i]) {
        case 'date':
          _mapping.dateColumn = i;
        case 'amount':
          _mapping.amountColumn = i;
        case 'debit':
          _mapping.debitColumn = i;
        case 'credit':
          _mapping.creditColumn = i;
        case 'description':
          _mapping.descriptionColumn = i;
      }
    }
  }

  bool get _canParse =>
      _mapping.dateColumn != null &&
      _mapping.descriptionColumn != null &&
      (_mapping.amountColumn != null ||
          (_mapping.debitColumn != null || _mapping.creditColumn != null));

  Future<void> _parse() async {
    if (!_canParse || widget.result.rawCsvContent == null) return;
    setState(() => _parsing = true);
    try {
      final txns = await app.importService.parseWithMapping(
        widget.result.rawCsvContent!,
        _mapping,
        sourceId: widget.sourceId,
      );
      // Saved only once it has read something. It was saved before parsing,
      // so a layout that read nothing was still tried first on every later
      // import of the source.
      if (_saveMapping && txns != null && txns.isNotEmpty) {
        await app.importService.saveColumnMapping(widget.sourceId, _mapping);
      }
      await app.importService.prepareForReview(txns ?? [], widget.sourceId);
      if (!mounted) return;
      final newResult = ImportResult(
        transactions: txns ?? [],
        tierUsed: ImportTier.manual,
        fileType: widget.result.fileType,
        fileName: widget.result.fileName,
        needsManualMapping: false,
      );
      // Pushed, not replaced, so backing out of the preview returns here to
      // fix a column rather than to the start with every choice lost.
      final route = ModalRoute.of(context);
      final imported = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder:
              (_) => ImportPreviewScreen(
                result: newResult,
                sourceId: widget.sourceId,
                sourceName: widget.sourceName,
              ),
        ),
      );
      // Once imported, the summary sits on top; take this screen out from
      // under it, so its Done returns to the import screen.
      if (imported == true && mounted && route != null) {
        Navigator.of(context).removeRoute(route);
      }
    } catch (e) {
      // A try with no catch: a failure here was an unhandled error, and the
      // button simply stopped spinning (audit U-6).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read the file this way: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Map Columns')),
      body: Column(
        children: [
          // Instruction banner
          Container(
            width: double.infinity,
            color: cs.primaryContainer.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              'Assign each column from your CSV to a field below. '
              'At minimum you need: Date, Description, and Amount (or Debit + Credit).',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurface),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // CSV preview table
                if (_headers.isNotEmpty) ...[
                  Text(
                    'File Preview',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 160,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowHeight: 36,
                          dataRowMinHeight: 28,
                          dataRowMaxHeight: 28,
                          columnSpacing: 16,
                          columns:
                              _headers
                                  .map(
                                    (h) => DataColumn(
                                      label: Text(
                                        h,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          rows:
                              _previewRows
                                  .map(
                                    (row) => DataRow(
                                      cells: List.generate(
                                        _headers.length,
                                        (i) => DataCell(
                                          Text(
                                            i < row.length ? row[i] : '',
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Column assignment
                Text(
                  'Column Assignments',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                ..._headers.asMap().entries.map((entry) {
                  final i = entry.key;
                  final h = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            h,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: _assignments[i],
                            isDense: true,
                            // Shortened to fit rather than overflowing:
                            // "Amount (signed)" ran past the edge at a large
                            // text size (audit T-1 found it).
                            isExpanded: true,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items:
                                _assignOptions
                                    .map(
                                      (o) => DropdownMenuItem(
                                        value: o.$1,
                                        child: Text(
                                          o.$2,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) => _onAssign(i, v!),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                // Date format picker (shown when date column is assigned)
                if (_mapping.dateColumn != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Date Format',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _mapping.dateFormat,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items:
                        _dateFormats
                            .map(
                              (f) => DropdownMenuItem(value: f, child: Text(f)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _mapping.dateFormat = v!),
                  ),
                ],

                // Live preview
                if (_canParse && _previewRows.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Preview (first ${_previewRows.length} rows)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  ..._previewRows.map((row) {
                    final dateStr =
                        _mapping.dateColumn != null &&
                                _mapping.dateColumn! < row.length
                            ? row[_mapping.dateColumn!]
                            : '?';
                    final descStr =
                        _mapping.descriptionColumn != null &&
                                _mapping.descriptionColumn! < row.length
                            ? row[_mapping.descriptionColumn!]
                            : '?';
                    final amtStr =
                        _mapping.amountColumn != null &&
                                _mapping.amountColumn! < row.length
                            ? row[_mapping.amountColumn!]
                            : '${_mapping.debitColumn != null && _mapping.debitColumn! < row.length ? row[_mapping.debitColumn!] : ''}'
                                '/'
                                '${_mapping.creditColumn != null && _mapping.creditColumn! < row.length ? row[_mapping.creditColumn!] : ''}';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        descStr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(dateStr),
                      trailing: Text(
                        amtStr,
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }),
                ],

                const SizedBox(height: 16),

                // Save mapping checkbox
                CheckboxListTile(
                  value: _saveMapping,
                  onChanged: (v) => setState(() => _saveMapping = v ?? true),
                  title: Text('Save mapping for "${widget.sourceName}"'),
                  subtitle: const Text(
                    'Reuse this column layout on future imports from this source.',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),

                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: _canParse && !_parsing ? _parse : null,
                  icon:
                      _parsing
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onBitcoinOrange,
                            ),
                          )
                          : const Icon(Icons.play_arrow),
                  label: const Text('Parse Transactions'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The date format of a column's [values], or null if they do not settle it.
///
/// Read from the whole column. It used to be the first three rows, so a UK
/// export whose first dates fell on the 12th or earlier — 01/03, 05/03,
/// 11/03 — was taken as month-first, and every later row after the 12th was
/// rejected (audit A-18). A stray line that is not a date, a total say, does
/// not block the guess as long as most of the column is dates.
String? guessDateFormat(List<String> values) {
  final dates = [
    for (final v in values)
      if (v.trim().isNotEmpty) v.trim(),
  ];
  if (dates.isEmpty) return null;
  bool most(int n) => n * 2 > dates.length;

  if (most(dates.where(RegExp(r'^\d{4}[-/.]\d{1,2}').hasMatch).length)) {
    return 'YYYY-MM-DD';
  }
  final numeric = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})(?!\d)');
  final matches = dates.map(numeric.firstMatch).whereType<RegExpMatch>();
  if (!most(matches.length)) return null;
  // A first part over 12 can only be a day. Without this, a DD/MM export
  // was offered as MM/DD and every date after the 12th was rejected.
  final dayFirst = matches.any((m) => int.parse(m.group(1)!) > 12);
  final shortYear = matches.every((m) => m.group(3)!.length == 2);
  return switch ((dayFirst, shortYear)) {
    (true, true) => 'DD/MM/YY',
    (true, false) => 'DD/MM/YYYY',
    (false, true) => 'MM/DD/YY',
    (false, false) => 'MM/DD/YYYY',
  };
}
