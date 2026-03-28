import 'dart:async';
import 'dart:convert';
import 'dart:io';


import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:drift/drift.dart' show Value, InsertMode, OrderingTerm;
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../database/database.dart';
import 'ollama_service.dart';
import '../../data/institution_profiles.dart';
import '../../shared/utils/hash_utils.dart';

/// Thrown when [ImportService.cancelImport] is called during an active import.
class ImportCancelledException implements Exception {
  const ImportCancelledException();
}

// ── Models ────────────────────────────────────────────────────────────────────

enum ImportTier { ollama, rules, manual, pdfExtracted, pdfHeuristic, image }

enum ImportFileType { csv, pdf, image, unknown }

class ParsedTransaction {
  ParsedTransaction({
    required this.date,
    required this.amount,
    required this.direction,
    required this.description,
    required this.rawDescription,
    required this.currency,
    this.category,
    this.include = true,
  });

  DateTime date;
  double amount; // always positive
  String direction; // 'debit' or 'credit'
  String description;
  String rawDescription;
  String currency;
  String? category;
  bool include;
}

class ColumnMapping {
  ColumnMapping({
    this.dateColumn,
    this.amountColumn,
    this.debitColumn,
    this.creditColumn,
    this.descriptionColumn,
    this.dateFormat = 'MM/DD/YYYY',
  });

  int? dateColumn;
  int? amountColumn;
  int? debitColumn;
  int? creditColumn;
  int? descriptionColumn;
  String dateFormat;

  Map<String, dynamic> toJson() => {
        'dateColumn': dateColumn,
        'amountColumn': amountColumn,
        'debitColumn': debitColumn,
        'creditColumn': creditColumn,
        'descriptionColumn': descriptionColumn,
        'dateFormat': dateFormat,
      };

  factory ColumnMapping.fromJson(Map<String, dynamic> json) => ColumnMapping(
        dateColumn: json['dateColumn'] as int?,
        amountColumn: json['amountColumn'] as int?,
        debitColumn: json['debitColumn'] as int?,
        creditColumn: json['creditColumn'] as int?,
        descriptionColumn: json['descriptionColumn'] as int?,
        dateFormat: (json['dateFormat'] as String?) ?? 'MM/DD/YYYY',
      );
}

class ImportResult {
  const ImportResult({
    required this.transactions,
    required this.fileType,
    required this.fileName,
    this.tierUsed,
    this.needsManualMapping = false,
    this.isPdfNoAi = false,
    this.pdfAiNotReady = false,
    this.pdfScanned = false,
    this.rawCsvContent,
    this.csvRows,
    this.csvHeaders,
  });

  final List<ParsedTransaction> transactions;
  final ImportTier? tierUsed;
  final bool needsManualMapping;
  /// True when PDF had no text to extract, or AI ran but returned no transactions.
  final bool isPdfNoAi;
  /// True when PDF text was extracted but no AI provider was connected/configured,
  /// and heuristic detection also failed to find enough transactions.
  final bool pdfAiNotReady;
  /// True when the PDF appears to be a scanned/image-only document (text layer
  /// extracted fewer than 50 characters).
  final bool pdfScanned;
  final ImportFileType fileType;
  final String fileName;
  final String? rawCsvContent;
  final List<List<String>>? csvRows;
  final List<String>? csvHeaders;
}

class ImportSummary {
  const ImportSummary({
    required this.imported,
    required this.duplicatesSkipped,
    required this.total,
    required this.sourceName,
    required this.sourceId,
    this.startDate,
    this.endDate,
  });

  final int imported;
  final int duplicatesSkipped;
  final int total;
  final String sourceName;
  final int sourceId;
  final DateTime? startDate;
  final DateTime? endDate;
}

// ── Service ───────────────────────────────────────────────────────────────────

class ImportService {
  ImportService(this.db, this.ollama);

  final AppDatabase db;
  final OllamaService ollama;

  // ── Import progress / cancellation ───────────────────────────────────────

  // sync: true delivers each token to the listener immediately when add() is
  // called, rather than scheduling a microtask. Without this, all tokens are
  // queued and delivered after the await-for loop exits, causing the entire
  // model output to appear at once instead of progressively.
  final _tokenController = StreamController<String>.broadcast(sync: true);
  http.Client? _activeImportClient;
  bool _importCancelled = false;

  /// Stream of raw AI response tokens emitted during Tier 1 Ollama parsing.
  /// Subscribe while an import is running to show live model output.
  Stream<String> get importTokenStream => _tokenController.stream;

  /// Aborts the in-flight Ollama request and signals the import to stop.
  void cancelImport() {
    _importCancelled = true;
    _activeImportClient?.close();
    _activeImportClient = null;
  }

  void _resetImportState() {
    _importCancelled = false;
    _activeImportClient = null;
  }

  void _checkCancelled() {
    if (_importCancelled) throw const ImportCancelledException();
  }

  // ── Public entry point ───────────────────────────────────────────────────

  /// Tries tiers in order: saved mapping → Ollama → rules → manual mapping signal.
  /// For PDFs: extracts text then tries Ollama; falls back to isPdfNoAi.
  ///
  /// [onStageChange] is called with a human-readable string at each processing
  /// stage so the UI can show meaningful progress. Throws [ImportCancelledException]
  /// if [cancelImport] is called during processing.
  Future<ImportResult> importFile({
    required String filePath,
    required String fileName,
    required int sourceId,
    void Function(String stage)? onStageChange,
  }) async {
    _resetImportState();
    final lname = fileName.toLowerCase();
    final fileType = lname.endsWith('.pdf')
        ? ImportFileType.pdf
        : lname.endsWith('.csv')
            ? ImportFileType.csv
            : ImportFileType.unknown;

    if (fileType == ImportFileType.pdf) {
      return _handlePdf(filePath, fileName, sourceId,
          onStageChange: onStageChange);
    }

    return _handleCsv(filePath, fileName, sourceId,
        onStageChange: onStageChange);
  }

  /// Entry point for image import (camera or photo library).
  /// Sends the image to the active AI provider using the vision API and parses
  /// the returned JSON into [ParsedTransaction]s.
  Future<ImportResult> importImage({
    required String imagePath,
    required int sourceId,
    void Function(String stage)? onStageChange,
  }) async {
    _resetImportState();
    final fileName = imagePath.contains('/')
        ? imagePath.split('/').last
        : imagePath.split('\\').last;
    return _handleImage(imagePath, fileName, sourceId,
        onStageChange: onStageChange);
  }

  /// Reads a CSV file and returns an [ImportResult] ready for the manual
  /// column mapper screen. Used when falling back from a timeout.
  Future<ImportResult> readCsvForManualMapping(
      String filePath, String fileName) async {
    try {
      final content = await File(filePath).readAsString();
      final allRows = _parseCsvRows(content);
      return ImportResult(
        transactions: [],
        needsManualMapping: true,
        fileType: ImportFileType.csv,
        fileName: fileName,
        rawCsvContent: content,
        csvRows: allRows,
        csvHeaders: allRows.isNotEmpty ? allRows[0] : [],
      );
    } catch (_) {
      return ImportResult(
          transactions: [], fileType: ImportFileType.csv, fileName: fileName);
    }
  }

  // ── PDF flow ─────────────────────────────────────────────────────────────

  Future<ImportResult> _handlePdf(
    String filePath,
    String fileName,
    int sourceId, {
    void Function(String)? onStageChange,
  }) async {
    onStageChange?.call('Reading your statement…');
    // Let the UI render the first stage before blocking on I/O
    await Future.delayed(const Duration(milliseconds: 60));
    _checkCancelled();

    onStageChange?.call('Extracting text from PDF…');
    final text = await extractPdfText(filePath);
    _checkCancelled();

    if (text == null || text.trim().length < 50) {
      return ImportResult(
        transactions: [],
        fileType: ImportFileType.pdf,
        fileName: fileName,
        pdfScanned: true,
      );
    }

    final ollamaReady =
        await ollama.isAvailable() && (ollama.selectedModel?.isNotEmpty ?? false);
    _checkCancelled();

    if (!ollamaReady) {
      onStageChange?.call('Attempting heuristic detection…');
      await Future.delayed(const Duration(milliseconds: 60));
      final heuristicTxns = _parseTransactionsFromPdfText(text);
      if (heuristicTxns.length >= 3) {
        return ImportResult(
          transactions: heuristicTxns,
          tierUsed: ImportTier.pdfHeuristic,
          fileType: ImportFileType.pdf,
          fileName: fileName,
        );
      }
      return ImportResult(
        transactions: [],
        fileType: ImportFileType.pdf,
        fileName: fileName,
        pdfAiNotReady: true,
      );
    }

    final txns =
        await parseWithOllama(text, onStageChange: onStageChange);
    _checkCancelled();

    return ImportResult(
      transactions: txns ?? [],
      tierUsed: txns != null ? ImportTier.ollama : null,
      isPdfNoAi: txns == null || txns.isEmpty,
      fileType: ImportFileType.pdf,
      fileName: fileName,
    );
  }

  // ── Image flow ───────────────────────────────────────────────────────────

  Future<ImportResult> _handleImage(
    String imagePath,
    String fileName,
    int sourceId, {
    void Function(String)? onStageChange,
  }) async {
    onStageChange?.call('Preparing image…');
    await Future.delayed(const Duration(milliseconds: 60));
    _checkCancelled();

    // Read bytes and base64-encode
    final imageBytes = await File(imagePath).readAsBytes();
    final lower = imagePath.toLowerCase();
    final mimeType = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
    final base64Image = base64Encode(imageBytes);
    _checkCancelled();

    const prompt = '''You are a financial data extraction assistant. This image shows a bank statement, credit card statement, or financial document. Extract every transaction you can see and return them as a JSON array.

Each transaction must have these exact fields:
- "date": ISO 8601 date string (YYYY-MM-DD)
- "amount": positive decimal number (always positive)
- "direction": "debit" (money leaving) or "credit" (money arriving)
- "description": merchant or transaction description
- "currency": 3-letter currency code (USD, EUR, GBP, BTC, etc.)

Rules:
- Skip any header rows, totals, opening/closing balances, or non-transaction rows
- If a row has separate debit and credit columns, use the non-zero value and set direction accordingly
- If you cannot confidently read a value, skip that transaction
- Return ONLY the JSON array, no explanation, no markdown, no code fences''';

    final client = http.Client();
    _activeImportClient = client;

    try {
      onStageChange?.call('Sending to ${ollama.selectedModel ?? 'AI'}…');
      await Future.delayed(const Duration(milliseconds: 60));
      onStageChange?.call('AI is reading your statement…');

      final buffer = StringBuffer();
      var tokenCount = 0;
      await for (final token in ollama.chatWithImage(
        prompt,
        base64Image,
        mimeType: mimeType,
        client: client,
      )) {
        if (_importCancelled) break;
        buffer.write(token);
        _tokenController.add(token);
        tokenCount++;
        if (tokenCount % 5 == 0) await Future<void>.delayed(Duration.zero);
      }
      _checkCancelled();

      onStageChange?.call('Processing results…');

      final jsonArray = _extractJsonArray(buffer.toString().trim());
      if (jsonArray == null) {
        return ImportResult(
          transactions: [],
          fileType: ImportFileType.image,
          fileName: fileName,
          isPdfNoAi: true,
        );
      }

      final parsed = jsonArray
          .map((item) {
            try {
              final map = item as Map<String, dynamic>;
              final date = DateTime.tryParse((map['date'] as String?) ?? '');
              if (date == null) return null;
              final amount = (map['amount'] as num?)?.toDouble();
              if (amount == null) return null;
              final direction =
                  ((map['direction'] as String?) ?? 'debit').toLowerCase();
              final description = (map['description'] as String?) ?? '';
              final currency =
                  ((map['currency'] as String?) ?? 'USD').toUpperCase();
              return ParsedTransaction(
                date: date,
                amount: amount.abs(),
                direction: direction == 'credit' ? 'credit' : 'debit',
                description: description,
                rawDescription: description,
                currency: currency,
                category: _autoCategory(description),
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<ParsedTransaction>()
          .toList();

      return ImportResult(
        transactions: parsed,
        tierUsed: parsed.isNotEmpty ? ImportTier.image : null,
        isPdfNoAi: parsed.isEmpty,
        fileType: ImportFileType.image,
        fileName: fileName,
      );
    } on ImportCancelledException {
      rethrow;
    } catch (_) {
      if (_importCancelled) throw const ImportCancelledException();
      return ImportResult(
        transactions: [],
        fileType: ImportFileType.image,
        fileName: fileName,
        isPdfNoAi: true,
      );
    } finally {
      _activeImportClient = null;
      client.close();
    }
  }

  // ── CSV flow ─────────────────────────────────────────────────────────────

  Future<ImportResult> _handleCsv(
    String filePath,
    String fileName,
    int sourceId, {
    void Function(String)? onStageChange,
  }) async {
    onStageChange?.call('Reading your statement…');
    await Future.delayed(const Duration(milliseconds: 60));
    _checkCancelled();

    final String content;
    try {
      content = await File(filePath).readAsString();
    } catch (_) {
      return ImportResult(
          transactions: [], fileType: ImportFileType.csv, fileName: fileName);
    }
    _checkCancelled();

    final allRows = _parseCsvRows(content);
    if (allRows.isEmpty) {
      return ImportResult(
          transactions: [], fileType: ImportFileType.csv, fileName: fileName);
    }

    // --- Check for a saved column mapping on this source ---
    final source = await (db.select(db.importSources)
          ..where((t) => t.id.equals(sourceId)))
        .getSingleOrNull();
    _checkCancelled();

    if (source?.columnMapping != null) {
      try {
        final mapping =
            ColumnMapping.fromJson(jsonDecode(source!.columnMapping!) as Map<String, dynamic>);
        final txns = await parseWithMapping(content, mapping);
        if (txns != null && txns.isNotEmpty) {
          return ImportResult(
            transactions: txns,
            tierUsed: ImportTier.manual,
            fileType: ImportFileType.csv,
            fileName: fileName,
          );
        }
      } catch (_) {
        // Corrupted mapping — fall through
      }
    }
    _checkCancelled();

    // --- Tier 1: Ollama ---
    final ollamaReady =
        await ollama.isAvailable() && (ollama.selectedModel?.isNotEmpty ?? false);
    _checkCancelled();

    if (ollamaReady) {
      final txns =
          await parseWithOllama(content, onStageChange: onStageChange);
      _checkCancelled();
      if (txns != null && txns.isNotEmpty) {
        return ImportResult(
          transactions: txns,
          tierUsed: ImportTier.ollama,
          fileType: ImportFileType.csv,
          fileName: fileName,
        );
      }
    }

    // --- Tier 2: Rule-based ---
    onStageChange?.call('Applying smart rules…');
    final txns = await parseWithRules(content);
    _checkCancelled();

    if (txns != null && txns.isNotEmpty) {
      return ImportResult(
        transactions: txns,
        tierUsed: ImportTier.rules,
        fileType: ImportFileType.csv,
        fileName: fileName,
      );
    }

    // --- Tier 3 signal: manual column mapping needed ---
    final rawHeaders = allRows[0];
    return ImportResult(
      transactions: [],
      needsManualMapping: true,
      fileType: ImportFileType.csv,
      fileName: fileName,
      rawCsvContent: content,
      csvRows: allRows,
      csvHeaders: rawHeaders,
    );
  }

  // ── Tier 1: Ollama ────────────────────────────────────────────────────────

  Future<List<ParsedTransaction>?> parseWithOllama(
    String content, {
    void Function(String)? onStageChange,
  }) async {
    final client = http.Client();
    _activeImportClient = client;

    try {
      const maxLen = 100000;
      final truncated =
          content.length > maxLen ? content.substring(0, maxLen) : content;

      const prefix = '''You are a financial data parser. Extract every transaction from this bank/exchange statement and return them as a JSON array.

Each transaction must have these exact fields:
- "date": ISO 8601 date string (YYYY-MM-DD)
- "amount": positive decimal number (always positive, never negative)
- "direction": "debit" (money leaving) or "credit" (money arriving)
- "description": the merchant, payee name, or transaction description
- "currency": 3-letter currency code (USD, EUR, BTC, etc.)

Rules:
- If the file uses separate Debit and Credit columns, use the non-zero one and set direction accordingly
- If the file uses a single signed amount column, negative = debit, positive = credit
- Skip any header rows, summary rows, totals, or opening/closing balance rows
- If you cannot confidently parse a row, skip it rather than guessing
- Return ONLY the JSON array, no explanation, no markdown, no code fences

FILE CONTENT:
''';

      final messages = [
        {'role': 'user', 'content': '$prefix$truncated'},
      ];

      onStageChange
          ?.call('Sending to ${ollama.selectedModel ?? 'AI'} for analysis…');
      await Future.delayed(const Duration(milliseconds: 60));
      onStageChange?.call('AI is thinking…');

      final buffer = StringBuffer();
      var tokenCount = 0;
      await for (final token in ollama.chat(messages, client: client)) {
        if (_importCancelled) break;
        buffer.write(token);
        _tokenController.add(token); // sync: true — delivered immediately to UI
        tokenCount++;
        // Yield to the event loop every 5 tokens. Without this, Dart's
        // microtask queue processes all tokens before Flutter can schedule
        // a frame, so the UI only redraws once after generation completes.
        if (tokenCount % 5 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      _checkCancelled();

      onStageChange?.call('Processing results…');

      final jsonArray = _extractJsonArray(buffer.toString().trim());
      if (jsonArray == null) return null;

      final parsed = jsonArray
          .map((item) {
            try {
              final map = item as Map<String, dynamic>;
              final date = DateTime.tryParse((map['date'] as String?) ?? '');
              if (date == null) return null;
              final amount = (map['amount'] as num?)?.toDouble();
              if (amount == null) return null;
              final direction =
                  ((map['direction'] as String?) ?? 'debit').toLowerCase();
              final description = (map['description'] as String?) ?? '';
              final currency =
                  ((map['currency'] as String?) ?? 'USD').toUpperCase();
              return ParsedTransaction(
                date: date,
                amount: amount.abs(),
                direction: direction == 'credit' ? 'credit' : 'debit',
                description: description,
                rawDescription: description,
                currency: currency,
                category: _autoCategory(description),
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<ParsedTransaction>()
          .toList();

      return parsed;
    } on ImportCancelledException {
      rethrow;
    } catch (_) {
      if (_importCancelled) throw const ImportCancelledException();
      return null;
    } finally {
      _activeImportClient = null;
      client.close();
    }
  }

  // ── Tier 2: Rule-based CSV parsing ───────────────────────────────────────

  Future<List<ParsedTransaction>?> parseWithRules(String csvContent) async {
    final allRows = _parseCsvRows(csvContent);
    if (allRows.length < 2) return null;

    final rawHeaders = allRows[0];
    final headers =
        rawHeaders.map((h) => h.toLowerCase().trim().replaceAll('"', '')).toList();

    // Try institution profile first
    final profile = InstitutionProfiles.detect(headers);
    if (profile != null) {
      return _parseWithProfile(allRows, headers, profile);
    }

    // Generic header detection
    const dateNames = {
      'date', 'transaction date', 'posted date', 'posting date',
      'trans date', 'value date', 'trade date',
    };
    const amountNames = {'amount', 'transaction amount', 'total'};
    const debitNames = {
      'debit', 'withdrawals', 'withdrawal', 'debit amount', 'charges', 'out'
    };
    const creditNames = {
      'credit', 'deposits', 'deposit', 'credit amount', 'payments', 'in'
    };
    const descNames = {
      'description', 'memo', 'narrative', 'payee', 'merchant', 'details',
      'transaction description', 'particulars', 'name',
    };

    int? dateCol, amountCol, debitCol, creditCol, descCol;
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (dateCol == null && dateNames.contains(h)) dateCol = i;
      if (amountCol == null && amountNames.contains(h)) amountCol = i;
      if (debitCol == null && debitNames.contains(h)) debitCol = i;
      if (creditCol == null && creditNames.contains(h)) creditCol = i;
      if (descCol == null && descNames.contains(h)) descCol = i;
    }

    if (dateCol == null || descCol == null) return null;
    if (amountCol == null && (debitCol == null || creditCol == null)) {
      return null;
    }

    return _parseRowsGeneric(
      allRows,
      dateCol: dateCol,
      descCol: descCol,
      amountCol: amountCol,
      debitCol: debitCol,
      creditCol: creditCol,
      signedAmount: amountCol != null,
      currency: 'USD',
    );
  }

  List<ParsedTransaction>? _parseWithProfile(
    List<List<String>> allRows,
    List<String> headers,
    InstitutionProfile profile,
  ) {
    int? dateCol, descCol, amountCol, debitCol, creditCol;

    if (profile.positional) {
      dateCol = profile.dateColumn;
      descCol = profile.descriptionColumn;
      amountCol = profile.amountColumn;
    } else {
      dateCol =
          profile.dateHeader != null ? headers.indexOf(profile.dateHeader!) : null;
      descCol = profile.descriptionHeader != null
          ? headers.indexOf(profile.descriptionHeader!)
          : null;
      amountCol = profile.amountHeader != null
          ? headers.indexOf(profile.amountHeader!)
          : null;
      debitCol = profile.debitHeader != null
          ? headers.indexOf(profile.debitHeader!)
          : null;
      creditCol = profile.creditHeader != null
          ? headers.indexOf(profile.creditHeader!)
          : null;
      if (dateCol == -1) dateCol = null;
      if (descCol == -1) descCol = null;
      if (amountCol == -1) amountCol = null;
      if (debitCol == -1) debitCol = null;
      if (creditCol == -1) creditCol = null;
    }

    if (dateCol == null) return null;

    return _parseRowsGeneric(
      allRows,
      dateCol: dateCol,
      descCol: descCol,
      amountCol: amountCol,
      debitCol: debitCol,
      creditCol: creditCol,
      signedAmount: profile.signedAmount,
      currency: profile.defaultCurrency,
    );
  }

  List<ParsedTransaction>? _parseRowsGeneric(
    List<List<String>> allRows, {
    required int? dateCol,
    required int? descCol,
    required int? amountCol,
    required int? debitCol,
    required int? creditCol,
    required bool signedAmount,
    required String currency,
  }) {
    if (dateCol == null) return null;

    final result = <ParsedTransaction>[];
    for (int i = 1; i < allRows.length; i++) {
      final row = allRows[i];
      if (row.every((e) => e.trim().isEmpty)) continue;

      final date =
          dateCol < row.length ? _parseDate(row[dateCol]) : null;
      if (date == null) continue;

      final description =
          (descCol != null && descCol < row.length) ? row[descCol].trim() : '';
      if (description.isEmpty) continue;

      double? amount;
      String direction;

      if (amountCol != null && amountCol < row.length) {
        final raw = _parseAmount(row[amountCol]);
        if (raw == null) continue;
        if (signedAmount) {
          amount = raw.abs();
          direction = raw < 0 ? 'debit' : 'credit';
        } else {
          amount = raw.abs();
          direction = 'debit'; // default for unsigned single-column amounts
        }
      } else {
        final dAmt = (debitCol != null && debitCol < row.length)
            ? _parseAmount(row[debitCol])
            : null;
        final cAmt = (creditCol != null && creditCol < row.length)
            ? _parseAmount(row[creditCol])
            : null;
        if (dAmt != null && dAmt.abs() > 0) {
          amount = dAmt.abs();
          direction = 'debit';
        } else if (cAmt != null && cAmt.abs() > 0) {
          amount = cAmt.abs();
          direction = 'credit';
        } else {
          continue;
        }
      }

      result.add(ParsedTransaction(
        date: date,
        amount: amount,
        direction: direction,
        description: description,
        rawDescription: description,
        currency: currency,
        category: _autoCategory(description),
      ));
    }
    return result.isEmpty ? null : result;
  }

  // ── Tier 3: Manual column mapping ─────────────────────────────────────────

  Future<List<ParsedTransaction>?> parseWithMapping(
    String csvContent,
    ColumnMapping mapping,
  ) async {
    final allRows = _parseCsvRows(csvContent);
    if (allRows.length < 2) return null;

    final result = <ParsedTransaction>[];
    for (int i = 1; i < allRows.length; i++) {
      final row = allRows[i];
      if (row.every((e) => e.trim().isEmpty)) continue;

      DateTime? date;
      if (mapping.dateColumn != null && mapping.dateColumn! < row.length) {
        date = _parseDateWithFormat(row[mapping.dateColumn!], mapping.dateFormat);
      }
      if (date == null) continue;

      final description = (mapping.descriptionColumn != null &&
              mapping.descriptionColumn! < row.length)
          ? row[mapping.descriptionColumn!].trim()
          : '';
      if (description.isEmpty) continue;

      double? amount;
      String direction;

      if (mapping.amountColumn != null && mapping.amountColumn! < row.length) {
        final raw = _parseAmount(row[mapping.amountColumn!]);
        if (raw == null) continue;
        amount = raw.abs();
        direction = raw < 0 ? 'debit' : 'credit';
      } else {
        final dAmt = (mapping.debitColumn != null && mapping.debitColumn! < row.length)
            ? _parseAmount(row[mapping.debitColumn!])
            : null;
        final cAmt = (mapping.creditColumn != null &&
                mapping.creditColumn! < row.length)
            ? _parseAmount(row[mapping.creditColumn!])
            : null;
        if (dAmt != null && dAmt.abs() > 0) {
          amount = dAmt.abs();
          direction = 'debit';
        } else if (cAmt != null && cAmt.abs() > 0) {
          amount = cAmt.abs();
          direction = 'credit';
        } else {
          continue;
        }
      }

      result.add(ParsedTransaction(
        date: date,
        amount: amount,
        direction: direction,
        description: description,
        rawDescription: description,
        currency: 'USD',
        category: _autoCategory(description),
      ));
    }
    return result.isEmpty ? null : result;
  }

  // ── Tier 4: PDF text extraction ───────────────────────────────────────────

  Future<String?> extractPdfText(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      final text = extractor.extractText();
      document.dispose();
      return text.trim().isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  // ── Save to database ──────────────────────────────────────────────────────

  Future<ImportSummary> saveTransactions({
    required List<ParsedTransaction> transactions,
    required int sourceId,
    required String sourceName,
    double? btcPrice,
  }) async {
    // Look up the default wallet to use as FK for main transactions table
    final wallets = await db.select(db.wallets).get();
    final walletId = wallets.isNotEmpty ? wallets.first.id : null;

    // Load all existing hashes for this source to detect duplicates
    final existingRows = await (db.select(db.importedTransactions)
          ..where((t) => t.sourceId.equals(sourceId)))
        .get();
    final existingHashes = {for (final r in existingRows) r.importHash};

    int imported = 0;
    int duplicatesSkipped = 0;
    DateTime? startDate;
    DateTime? endDate;

    final toInsert = transactions.where((t) => t.include).toList();

    for (final tx in toInsert) {
      final cents = _toSmallestUnit(tx.amount, tx.currency);
      final hash = computeHash(sourceId, tx.date, cents, tx.rawDescription);

      if (existingHashes.contains(hash)) {
        duplicatesSkipped++;
        continue;
      }

      try {
        await db.into(db.importedTransactions).insert(
          ImportedTransactionsCompanion.insert(
            sourceId: sourceId,
            date: tx.date,
            amountCents: cents,
            direction: tx.direction,
            description: tx.description,
            category: Value(tx.category),
            currency: tx.currency,
            rawDescription: tx.rawDescription,
            importHash: hash,
          ),
          mode: InsertMode.insertOrIgnore,
        );
        existingHashes.add(hash);
        imported++;
        if (startDate == null || tx.date.isBefore(startDate)) startDate = tx.date;
        if (endDate == null || tx.date.isAfter(endDate)) endDate = tx.date;
      } catch (_) {
        duplicatesSkipped++;
        continue;
      }

      // Also write into the main transactions table so the Transactions screen
      // can display imported data alongside manual and xpub entries.
      if (walletId != null) {
        final isBitcoin = tx.currency == 'BTC' || tx.currency == 'SATS';
        // fiatCurrency must be exactly 3 chars; SATS → BTC, others kept as-is
        final fiatCurrency = tx.currency == 'SATS'
            ? 'BTC'
            : (tx.currency.length == 3 ? tx.currency : 'USD');
        // signed: credit = positive, debit = negative
        final signedFiat = tx.direction == 'credit' ? tx.amount : -tx.amount;
        int amountSats;
        if (isBitcoin) {
          amountSats = tx.direction == 'credit' ? cents : -cents;
        } else if (btcPrice != null && btcPrice > 0) {
          amountSats = (signedFiat / btcPrice * 100000000).round();
        } else {
          amountSats = 0;
        }
        final dedupHash = HashUtils.transactionDedupHash(
          date: tx.date,
          amount: tx.amount,
          description: tx.rawDescription,
        );
        try {
          await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              walletId: walletId,
              date: tx.date,
              description: tx.description,
              amountFiat: signedFiat,
              amountSats: amountSats,
              fiatCurrency: fiatCurrency,
              category: Value(tx.category),
              source: 'csv',
              isBitcoin: Value(isBitcoin),
              dedupHash: dedupHash,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        } catch (_) {
          // Unique constraint violation — transaction already exists in main table
        }
      }
    }

    return ImportSummary(
      imported: imported,
      duplicatesSkipped: duplicatesSkipped,
      total: toInsert.length,
      sourceName: sourceName,
      sourceId: sourceId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  // ── Save / update column mapping on a source ─────────────────────────────

  Future<void> saveColumnMapping(int sourceId, ColumnMapping mapping) async {
    await (db.update(db.importSources)..where((t) => t.id.equals(sourceId)))
        .write(ImportSourcesCompanion(
          columnMapping: Value(jsonEncode(mapping.toJson())),
        ));
  }

  // ── Source CRUD ───────────────────────────────────────────────────────────

  Future<List<ImportSource>> listSources() =>
      db.select(db.importSources).get();

  Stream<List<ImportSource>> watchSources() =>
      db.select(db.importSources).watch();

  Future<int> createSource({
    required String name,
    required String type,
    required String currency,
  }) =>
      db.into(db.importSources).insert(
        ImportSourcesCompanion.insert(
          name: name,
          type: type,
          currency: currency,
        ),
      );

  Future<void> deleteSource(int id) async {
    await (db.delete(db.importedTransactions)
          ..where((t) => t.sourceId.equals(id)))
        .go();
    await (db.delete(db.importSources)..where((t) => t.id.equals(id))).go();
  }

  /// Returns imported transactions for [sourceId], newest first.
  Future<List<ImportedTransaction>> getTransactionsForSource(int sourceId) =>
      (db.select(db.importedTransactions)
            ..where((t) => t.sourceId.equals(sourceId))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .get();

  // ── Heuristic PDF parser (no-AI fallback) ────────────────────────────────

  /// Parses transactions from plain-text PDF content using pattern matching.
  /// Returns an empty list when fewer than 3 rows are found (low confidence).
  List<ParsedTransaction> _parseTransactionsFromPdfText(String text) {
    final lines = text.split(RegExp(r'\r?\n'));

    // Date patterns tried in order — take the first match per line.
    final datePats = <RegExp>[
      RegExp(r'\d{4}-\d{2}-\d{2}'),
      RegExp(r'\d{1,2}/\d{1,2}/\d{4}'),
      RegExp(r'\d{1,2}/\d{1,2}/\d{2}(?!\d)'),
      RegExp(
          r'\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}',
          caseSensitive: false),
      RegExp(
          r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\s+\d{4}',
          caseSensitive: false),
    ];

    // Matches currency amounts; requires decimal, thousands-comma, or currency
    // prefix — avoids matching plain integers like years or reference numbers.
    final amtPat = RegExp(
      r'[$£€][\d,]+(?:\.\d{1,2})?'           // $1,234 or £50.00
      r'|[-+]?\(?\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?\)?' // 1,234 or 1,234.56
      r'|[-+]?\(?\d+\.\d{1,2}\)?[-]?',       // 12.50 or -12.50 or (12.50)
    );

    // Noise tokens stripped from descriptions.
    final noisePat = RegExp(
      r'\b(?:ACH|POS|REF#?\w*|TXN\w*)\b',
      caseSensitive: false,
    );

    String columnCtx = 'debit'; // updated when column headers are detected
    final result = <ParsedTransaction>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // Update column context from header-like lines.
      final lower = line.toLowerCase();
      final hasDebit =
          lower.contains('withdrawal') || lower.contains('debit');
      final hasCredit =
          lower.contains('deposit') || lower.contains('credit');
      if (hasDebit && !hasCredit) columnCtx = 'debit';
      if (hasCredit && !hasDebit) columnCtx = 'credit';

      // Find the first date match on this line.
      RegExpMatch? dateMatch;
      for (final pat in datePats) {
        dateMatch = pat.firstMatch(line);
        if (dateMatch != null) break;
      }
      if (dateMatch == null) continue;

      final date = _parseDate(dateMatch.group(0)!);
      if (date == null) continue;

      // Find amounts outside the date region.
      final amtMatches = amtPat
          .allMatches(line)
          .where((m) =>
              m.end <= dateMatch!.start || m.start >= dateMatch.end)
          .toList();

      double amount;
      String direction;

      if (amtMatches.isEmpty) {
        // Look ahead up to 2 lines for an amount.
        double? lookAhead;
        for (int j = 1; j <= 2 && (i + j) < lines.length; j++) {
          for (final m in amtPat.allMatches(lines[i + j].trim())) {
            final p = _parseAmount(m.group(0)!);
            if (p != null && p.abs() > 0.001) {
              lookAhead = p;
              break;
            }
          }
          if (lookAhead != null) break;
        }
        if (lookAhead == null) continue;
        amount = lookAhead.abs();
        direction = lookAhead < 0 ? 'debit' : columnCtx;
      } else if (amtMatches.length >= 2) {
        // Two-column format: first column = withdrawals, second = deposits.
        // Whichever is non-zero is the transaction amount.
        final a = _parseAmount(amtMatches[0].group(0)!);
        final b = _parseAmount(amtMatches[1].group(0)!);
        if (a != null && a.abs() > 0.001) {
          amount = a.abs();
          direction = 'debit';
        } else if (b != null && b.abs() > 0.001) {
          amount = b.abs();
          direction = 'credit';
        } else {
          continue;
        }
      } else {
        final p = _parseAmount(amtMatches[0].group(0)!);
        if (p == null || p.abs() < 0.001) continue;
        amount = p.abs();
        direction = p < 0 ? 'debit' : columnCtx;
      }

      // Extract description: text between end of date and start of first amount.
      String desc;
      if (amtMatches.isNotEmpty && amtMatches.first.start > dateMatch.end) {
        desc = line.substring(dateMatch.end, amtMatches.first.start);
      } else {
        // Amounts precede date or no clear boundary — strip amounts from rest.
        desc = line.substring(dateMatch.end).replaceAll(amtPat, '');
      }

      desc = desc.replaceAll(noisePat, '');
      desc = desc.replaceAll(RegExp(r'[–—•*|:\t]+'), ' ');
      desc = desc.trim().replaceAll(RegExp(r'\s{2,}'), ' ');

      if (desc.length < 2) continue;

      result.add(ParsedTransaction(
        date: date,
        amount: amount,
        direction: direction,
        description: desc,
        rawDescription: desc,
        currency: 'USD',
        category: _autoCategory(desc),
      ));
    }

    return result;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String computeHash(
      int sourceId, DateTime date, int amountCents, String rawDescription) {
    final input =
        '$sourceId|${date.toIso8601String()}|$amountCents|$rawDescription';
    return sha256.convert(utf8.encode(input)).toString();
  }

  int _toSmallestUnit(double amount, String currency) {
    switch (currency.toUpperCase()) {
      case 'BTC':
        return (amount * 100000000).round();
      case 'SATS':
        return amount.round();
      default:
        return (amount * 100).round();
    }
  }

  List<List<String>> _parseCsvRows(String content) {
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(content);
    return rows.map((r) => r.map((e) => e.toString()).toList()).toList();
  }

  List<dynamic>? _extractJsonArray(String text) {
    // Direct parse
    try {
      final decoded = jsonDecode(text.trim());
      if (decoded is List) return decoded;
    } catch (_) {}
    // Strip markdown code fences
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fence != null) {
      try {
        final decoded = jsonDecode(fence.group(1)!.trim());
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    // Find first [ ... last ]
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start != -1 && end > start) {
      try {
        final decoded = jsonDecode(text.substring(start, end + 1));
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    return null;
  }

  // 2-digit year: 00–29 → 2000–2029, 30–99 → 1930–1999 (standard bank convention)
  int _expandYear(int yy) => yy <= 29 ? 2000 + yy : 1900 + yy;

  DateTime? _parseDate(String raw) {
    raw = raw.trim().replaceAll('"', '');
    if (raw.isEmpty) return null;

    // YYYY-MM-DD or YYYY-MM-DDTHH:mm
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (iso != null) {
      return DateTime.tryParse(
          '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}');
    }
    // YYYY/MM/DD
    final isoSlash = RegExp(r'^(\d{4})/(\d{2})/(\d{2})').firstMatch(raw);
    if (isoSlash != null) {
      return DateTime.tryParse(
          '${isoSlash.group(1)}-${isoSlash.group(2)}-${isoSlash.group(3)}');
    }
    // MM/DD/YYYY (US, 4-digit year)
    final us = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(raw);
    if (us != null) {
      final mo = int.parse(us.group(1)!);
      final dy = int.parse(us.group(2)!);
      final yr = int.parse(us.group(3)!);
      if (mo <= 12 && dy <= 31) return DateTime(yr, mo, dy);
    }
    // M/D/YY, M/DD/YY, MM/DD/YY (US 2-digit year — not followed by another digit)
    final us2 = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2})(?!\d)').firstMatch(raw);
    if (us2 != null) {
      final mo = int.parse(us2.group(1)!);
      final dy = int.parse(us2.group(2)!);
      final yr = _expandYear(int.parse(us2.group(3)!));
      if (mo <= 12 && dy <= 31) return DateTime(yr, mo, dy);
    }
    // DD/MM/YYYY or DD-MM-YYYY (UK)
    final uk = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(raw);
    if (uk != null) {
      final dy = int.parse(uk.group(1)!);
      final mo = int.parse(uk.group(2)!);
      final yr = int.parse(uk.group(3)!);
      if (mo <= 12 && dy <= 31) return DateTime(yr, mo, dy);
    }
    // DD MMM YYYY  or  MMM DD YYYY
    final months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final dmy =
        RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})').firstMatch(raw);
    if (dmy != null) {
      final mo = months[dmy.group(2)!.toLowerCase()];
      if (mo != null) {
        return DateTime(int.parse(dmy.group(3)!), mo, int.parse(dmy.group(1)!));
      }
    }
    final mdy =
        RegExp(r'^([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})').firstMatch(raw);
    if (mdy != null) {
      final mo = months[mdy.group(1)!.toLowerCase()];
      if (mo != null) {
        return DateTime(int.parse(mdy.group(3)!), mo, int.parse(mdy.group(2)!));
      }
    }
    return null;
  }

  DateTime? _parseDateWithFormat(String raw, String format) {
    raw = raw.trim().replaceAll('"', '');
    if (raw.isEmpty) return null;
    if (format == 'YYYY-MM-DD') return DateTime.tryParse(raw);
    if (format == 'MM/DD/YYYY') {
      final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(raw);
      if (m != null) {
        return DateTime.tryParse(
            '${m.group(3)}-${m.group(1)!.padLeft(2, '0')}-${m.group(2)!.padLeft(2, '0')}');
      }
    }
    if (format == 'DD/MM/YYYY') {
      final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(raw);
      if (m != null) {
        return DateTime.tryParse(
            '${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}');
      }
    }
    if (format == 'MM-DD-YYYY') {
      final m = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})').firstMatch(raw);
      if (m != null) {
        return DateTime.tryParse(
            '${m.group(3)}-${m.group(1)!.padLeft(2, '0')}-${m.group(2)!.padLeft(2, '0')}');
      }
    }
    if (format == 'MM/DD/YY') {
      final m =
          RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2})(?!\d)').firstMatch(raw);
      if (m != null) {
        final yr = _expandYear(int.parse(m.group(3)!));
        return DateTime(yr, int.parse(m.group(1)!), int.parse(m.group(2)!));
      }
    }
    return _parseDate(raw);
  }

  double? _parseAmount(String raw) {
    if (raw.trim().isEmpty) return null;
    var s = raw
        .trim()
        .replaceAll('"', '')
        .replaceAll(r'$', '')
        .replaceAll('£', '')
        .replaceAll('€', '')
        .replaceAll('₿', '');
    // Parenthetical negatives: (4.50) → -4.50
    final paren = RegExp(r'^\(([0-9,. ]+)\)$').firstMatch(s);
    if (paren != null) s = '-${paren.group(1)}';
    // Strip thousands separators and spaces
    s = s.replaceAll(',', '').replaceAll(' ', '');
    // Trailing minus sign: 4.50- → -4.50
    if (s.endsWith('-')) s = '-${s.substring(0, s.length - 1)}';
    return double.tryParse(s);
  }

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
      'waitrose', 'sainsbury', 'whole foods', 'trader joe', 'grocery',
      'supermarket', 'bakery', 'deli', 'dining', 'diner', 'panera',
      'dunkin', 'chick-fil',
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

  String _autoCategory(String description) {
    final lower = description.toLowerCase();
    for (final entry in _categoryKeywords.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }
    return 'Other';
  }
}

