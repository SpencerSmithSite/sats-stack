import 'dart:io';
import 'package:csv/csv.dart';
import 'package:drift/drift.dart' show Value;
import '../database/database.dart';
import '../../shared/utils/hash_utils.dart';
import '../../shared/constants/app_constants.dart';

enum BankFormat { chase, bofa, wellsFargo, barclays, hsbc, monzo, generic }

class CsvPreviewRow {
  CsvPreviewRow({
    required this.date,
    required this.amountFiat,
    required this.description,
    required this.category,
    required this.isDuplicate,
    this.include = true,
  });

  final DateTime date;
  final double amountFiat;
  final String description;
  final String category;
  final bool isDuplicate;
  bool include;
}

class CsvImportResult {
  CsvImportResult({
    required this.rows,
    required this.format,
    required this.duplicateCount,
    required this.parseErrorCount,
  });

  final List<CsvPreviewRow> rows;
  final BankFormat format;
  final int duplicateCount;
  final int parseErrorCount;
}

class CsvImportService {
  CsvImportService(this._db);

  final AppDatabase _db;

  static const _maxBatchSize = 100;

  // Auto-categorisation keyword map (first match wins, checked lowercase)
  static const _categoryKeywords = <String, List<String>>{
    'Bitcoin': [
      'coinbase', 'kraken', 'binance', 'river financial', 'strike',
      'bitcoin', 'btc', 'swan', 'cash app bitcoin', 'fold',
    ],
    'Income': [
      'payroll', 'salary', 'direct dep', 'zelle received',
      'venmo credit', 'payment received', 'refund', 'cashback', 'dividend',
      'interest paid', 'deposit',
    ],
    'Food & Dining': [
      'restaurant', 'cafe', 'coffee', 'pizza', 'burger', 'sushi',
      'mcdonald', 'starbucks', 'subway', 'chipotle', 'doordash',
      'ubereats', 'grubhub', 'deliveroo', 'just eat', 'tesco',
      'waitrose', 'sainsbury', 'whole foods', 'trader joe', 'aldi',
      'lidl', 'kroger', 'grocery', 'supermarket', 'bakery', 'deli',
      'dining', 'diner', 'panera', 'dunkin', 'chick-fil',
    ],
    'Transport': [
      'uber', 'lyft', 'taxi', 'transit', 'metro', 'bus ', 'train',
      'amtrak', 'flight', 'airline', 'parking', 'toll', ' gas ',
      'petrol', 'shell', 'bp ', 'exxon', 'chevron', 'fuel', 'tfl ',
      'oyster', 'national rail', 'ryanair', 'easyjet',
    ],
    'Housing': [
      'rent', 'mortgage', 'hoa ', 'electric', 'water bill',
      'internet', 'xfinity', 'comcast', 'at&t', 'verizon', 'spectrum',
      'landlord', 'property',
    ],
    'Subscriptions': [
      'netflix', 'spotify', 'hulu', 'disney+', 'apple subscription',
      'google one', 'youtube premium', 'patreon', 'twitch',
      'dropbox', 'icloud', 'microsoft 365', 'adobe',
      'subscription', 'annual fee', 'monthly fee',
    ],
    'Shopping': [
      'amazon', 'ebay', 'etsy', 'walmart', 'target', 'costco',
      'best buy', 'ikea', 'h&m', 'zara', 'nike', 'adidas',
      'clothing', 'apparel', 'shoes', 'shop',
    ],
    'Entertainment': [
      'cinema', 'movie', 'theater', 'concert', 'ticket',
      'eventbrite', 'ticketmaster', 'amc ', 'regal ', 'bar ',
      'bowling', 'gym', 'fitness', 'sport', 'steam ',
    ],
  };

  String _guessCategory(String description) {
    final lower = description.toLowerCase();
    for (final entry in _categoryKeywords.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }
    return 'Other';
  }

  BankFormat _detectFormat(List<String> headers) {
    final h = headers.map((e) => e.toLowerCase().trim().replaceAll('"', '')).toList();
    if (h.contains('transaction date') && h.contains('post date')) {
      return BankFormat.chase;
    }
    if (h.any((e) => e.contains('running bal'))) {
      return BankFormat.bofa;
    }
    if (h.contains('transaction id') && h.contains('type') && h.contains('emoji')) {
      return BankFormat.monzo;
    }
    if (h.any((e) => e == 'amount in') || h.any((e) => e == 'amount out')) {
      return BankFormat.hsbc;
    }
    // Wells Fargo: "Date","Amount","*","*","Description" — 5 cols, 3rd & 4th are '*'
    if (h.length >= 5 && h[2] == '*' && h[3] == '*') {
      return BankFormat.wellsFargo;
    }
    // Barclays: Date, Description, Amount (exactly 3 relevant cols)
    if (h.contains('date') && h.contains('description') && h.contains('amount') && h.length <= 5) {
      return BankFormat.barclays;
    }
    return BankFormat.generic;
  }

  DateTime? _parseDate(String raw) {
    raw = raw.trim().replaceAll('"', '');
    // YYYY-MM-DD
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');
    var m = iso.firstMatch(raw);
    if (m != null) {
      return DateTime.tryParse('${m.group(1)}-${m.group(2)}-${m.group(3)}');
    }
    // MM/DD/YYYY (US)
    final us = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})');
    m = us.firstMatch(raw);
    if (m != null) {
      final month = int.parse(m.group(1)!);
      final day = int.parse(m.group(2)!);
      final year = int.parse(m.group(3)!);
      if (month <= 12 && day <= 31) return DateTime(year, month, day);
    }
    // DD/MM/YYYY or DD-MM-YYYY (UK)
    final uk = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})');
    m = uk.firstMatch(raw);
    if (m != null) {
      final day = int.parse(m.group(1)!);
      final month = int.parse(m.group(2)!);
      final year = int.parse(m.group(3)!);
      if (month <= 12 && day <= 31) return DateTime(year, month, day);
    }
    return null;
  }

  double? _parseAmount(String raw) {
    if (raw.trim().isEmpty) return null;
    final cleaned = raw
        .trim()
        .replaceAll('"', '')
        .replaceAll(',', '')
        .replaceAll(r'$', '')
        .replaceAll('£', '')
        .replaceAll('€', '')
        .replaceAll(' ', '');
    return double.tryParse(cleaned);
  }

  List<String> _row(List<dynamic> raw) => raw.map((e) => e.toString()).toList();

  Future<CsvImportResult> parseFile(String filePath) async {
    final content = await File(filePath).readAsString();
    final allRows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(content);
    if (allRows.isEmpty) {
      return CsvImportResult(
          rows: [], format: BankFormat.generic, duplicateCount: 0, parseErrorCount: 0);
    }

    final headers = _row(allRows.first);
    final format = _detectFormat(headers);

    // Load existing dedup hashes for fast duplicate check
    final existing = await _db.select(_db.transactions).get();
    final existingHashes = {for (final t in existing) t.dedupHash};

    final preview = <CsvPreviewRow>[];
    int parseErrors = 0;
    int duplicates = 0;
    int batchSize = 0;

    for (int i = 1; i < allRows.length && batchSize < _maxBatchSize; i++) {
      final row = _row(allRows[i]);
      if (row.every((e) => e.trim().isEmpty)) continue;

      DateTime? date;
      double? amount;
      String description = '';

      try {
        switch (format) {
          case BankFormat.chase:
            // Transaction Date, Post Date, Description, Category, Type, Amount, Memo
            if (row.length < 6) { parseErrors++; continue; }
            date = _parseDate(row[0]);
            description = row[2].trim();
            amount = _parseAmount(row[5]);
          case BankFormat.bofa:
            // Date, Description, Amount, Running Bal.
            if (row.length < 3) { parseErrors++; continue; }
            date = _parseDate(row[0]);
            description = row[1].trim();
            amount = _parseAmount(row[2]);
          case BankFormat.wellsFargo:
            // "Date","Amount","*","*","Description"
            if (row.length < 5) { parseErrors++; continue; }
            date = _parseDate(row[0]);
            amount = _parseAmount(row[1]);
            description = row[4].trim();
          case BankFormat.monzo:
            // Transaction ID, Date, Time, Type, Name, Emoji, Category, Amount, Currency,...
            if (row.length < 8) { parseErrors++; continue; }
            date = _parseDate(row[1]);
            description = row[4].trim();
            amount = _parseAmount(row[7]);
          case BankFormat.hsbc:
            // Date, Payee, Memo, Amount In, Amount Out
            if (row.length < 5) { parseErrors++; continue; }
            date = _parseDate(row[0]);
            description = row[1].trim();
            final amountIn = _parseAmount(row[3]);
            final amountOut = _parseAmount(row[4]);
            if (amountIn != null && amountIn != 0) {
              amount = amountIn;
            } else if (amountOut != null && amountOut != 0) {
              amount = -amountOut.abs();
            }
          case BankFormat.barclays:
            // Date, Description, Amount
            if (row.length < 3) { parseErrors++; continue; }
            date = _parseDate(row[0]);
            description = row[1].trim();
            amount = _parseAmount(row[2]);
          case BankFormat.generic:
            for (int j = 0; j < row.length; j++) {
              final cell = row[j].trim();
              if (cell.isEmpty) continue;
              if (date == null) date = _parseDate(cell);
              if (amount == null && date != null) amount = _parseAmount(cell);
              if (description.isEmpty &&
                  double.tryParse(cell.replaceAll(',', '')) == null &&
                  _parseDate(cell) == null &&
                  cell.length > 2) {
                description = cell;
              }
            }
        }
      } catch (_) {
        parseErrors++;
        continue;
      }

      if (date == null || amount == null || description.isEmpty) {
        parseErrors++;
        continue;
      }

      final category = _guessCategory(description);
      final hash = HashUtils.transactionDedupHash(
        date: date,
        amount: amount,
        description: description,
      );
      final isDuplicate = existingHashes.contains(hash);
      if (isDuplicate) duplicates++;

      preview.add(CsvPreviewRow(
        date: date,
        amountFiat: amount,
        description: description,
        category: category,
        isDuplicate: isDuplicate,
        include: !isDuplicate,
      ));
      batchSize++;
    }

    return CsvImportResult(
      rows: preview,
      format: format,
      duplicateCount: duplicates,
      parseErrorCount: parseErrors,
    );
  }

  Future<int> importRows({
    required List<CsvPreviewRow> rows,
    required int walletId,
    required double? btcPrice,
  }) async {
    int imported = 0;
    for (final row in rows.where((r) => r.include && !r.isDuplicate)) {
      final hash = HashUtils.transactionDedupHash(
        date: row.date,
        amount: row.amountFiat,
        description: row.description,
      );
      final amountSats = (btcPrice != null && btcPrice > 0)
          ? (row.amountFiat / btcPrice * 100000000).round()
          : 0;
      try {
        await _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            walletId: walletId,
            date: row.date,
            description: row.description,
            amountFiat: row.amountFiat,
            amountSats: amountSats,
            fiatCurrency: AppConstants.defaultCurrency,
            category: Value(row.category),
            source: 'csv',
            dedupHash: hash,
          ),
        );
        imported++;
      } catch (_) {
        // Swallow unique-constraint violations from re-imported duplicates
      }
    }
    return imported;
  }
}
