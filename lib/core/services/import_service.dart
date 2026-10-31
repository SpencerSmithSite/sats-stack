import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:drift/drift.dart'
    show DoUpdate, InsertMode, StringExpressionOperators, Value;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../data/institution_profiles.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/hash_utils.dart';
import '../database/database.dart';
import '../models/ai_provider.dart';
import 'btc_price_service.dart';
import 'inference/inference_backend.dart';
import 'ollama_service.dart';

/// Cancels one import. Create one per import, pass it to
/// [ImportService.importFile] or [ImportService.importImage], and cancel it —
/// including when the screen that started it goes away.
class ImportCancelToken {
  bool _cancelled = false;
  http.Client? _client;

  bool get isCancelled => _cancelled;

  /// Stops the import at its next check, and aborts its in-flight request.
  void cancel() {
    _cancelled = true;
    _client?.close();
    _client = null;
  }

  /// The client the import's current AI request is using, so [cancel] can
  /// abort it. Closed at once if the import was already cancelled.
  void _attach(http.Client? client) {
    _client = client;
    if (_cancelled) client?.close();
  }
}

/// The state that belongs to one import rather than to the service.
class _ImportRun {
  _ImportRun(this.token);

  /// Outside any import: never cancelled, nothing consented to.
  static final none = _ImportRun(ImportCancelToken());

  final ImportCancelToken token;

  /// Set once the user has answered the off-device prompt, so a multi-tier
  /// import never asks twice.
  bool? consent;

  /// The user said yes, and it is to be remembered once the import completes —
  /// see `_finishImport`.
  bool rememberConsent = false;

  /// An off-device AI tier ran, so the file was uploaded.
  bool sent = false;

  /// How much of the file an AI tier was given, when that was not all of it.
  int? truncatedAt;
}

/// Thrown when an import's [ImportCancelToken] is cancelled during it.
class ImportCancelledException implements Exception {
  const ImportCancelledException();
}

// ── Models ────────────────────────────────────────────────────────────────────

enum ImportTier { ollama, rules, manual, pdfHeuristic, image }

enum ImportFileType { csv, pdf, image }

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
    this.categoryIsFallback = false,
    this.categoryIsUserChosen = false,
  });

  DateTime date;
  double amount; // always positive
  String direction; // 'debit' or 'credit'
  String description;
  String rawDescription;
  String currency;
  String? category;
  bool include;

  /// True when [category] came from the user rather than from the
  /// categoriser — either picked in the preview's edit sheet, or applied from
  /// a mapping learned from such a pick. Only these are learned.
  bool categoryIsUserChosen;

  /// True while [category] is only the fallback — no keyword matched the
  /// description.
  ///
  /// A fallback is not worth learning from. The import used to write a
  /// description → category mapping for every included row, `'Other'`
  /// included, and apply it to every future import of that source — so one
  /// unrecognised merchant was pinned to Other for good, even after the
  /// keyword list improved. That is the real reason "everything lands in
  /// Other" and stays there.
  bool categoryIsFallback;

  /// Sets a category the user (or a previously learned mapping) chose, which
  /// is by definition not a fallback.
  void setUserCategory(String? value) {
    category = value;
    categoryIsFallback = false;
    categoryIsUserChosen = true;
  }

  /// Set by [ImportService.markLikelyDuplicates] when the source already
  /// holds a row on this day for this amount and direction. Such a row starts
  /// unticked, and the preview labels it.
  bool likelyDuplicate = false;
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
    this.aiConsentDeclined = false,
    this.sentTo,
    this.aiLabel,
    this.aiInputTruncatedAt,
    this.errorMessage,
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

  /// True when reading this file needed a third party and the user said no.
  /// Not a failure — the file is untouched and nothing was sent.
  final bool aiConsentDeclined;

  /// Who was sent the file's contents to read it, phrased for a sentence, or
  /// null if nothing left the device. Set whenever an off-device AI tier ran
  /// — including when it then found nothing and a local tier took over, since
  /// the upload happened either way.
  ///
  /// Nothing used to say an upload had happened: one "Send" tap and every
  /// later import went out silently.
  final String? sentTo;

  /// The AI that read the file, by name ("Claude", "Ollama"), when an AI tier
  /// produced [transactions]. The preview used to say "Ollama AI" whichever
  /// provider it was.
  final String? aiLabel;

  /// Set when the file was longer than an AI request carries, to the number
  /// of characters that were sent: rows after that point were never read. It
  /// used to be cut without a word, so a long statement silently lost its
  /// last months.
  final int? aiInputTruncatedAt;

  /// Why nothing could be read, in words the user can act on, when the cause
  /// is known — for instance that the selected backend cannot read images.
  final String? errorMessage;
  final ImportFileType fileType;
  final String fileName;
  final String? rawCsvContent;
  final List<List<String>>? csvRows;
  final List<String>? csvHeaders;

  /// This result with who read it attached — see [sentTo] and [aiLabel].
  ImportResult withProvenance({
    String? sentTo,
    String? aiLabel,
    int? aiInputTruncatedAt,
  }) => ImportResult(
    transactions: transactions,
    fileType: fileType,
    fileName: fileName,
    tierUsed: tierUsed,
    needsManualMapping: needsManualMapping,
    isPdfNoAi: isPdfNoAi,
    pdfAiNotReady: pdfAiNotReady,
    pdfScanned: pdfScanned,
    aiConsentDeclined: aiConsentDeclined,
    sentTo: sentTo,
    aiLabel: aiLabel,
    aiInputTruncatedAt: aiInputTruncatedAt,
    errorMessage: errorMessage,
    rawCsvContent: rawCsvContent,
    csvRows: csvRows,
    csvHeaders: csvHeaders,
  );
}

class ImportSummary {
  const ImportSummary({
    required this.imported,
    required this.duplicatesSkipped,
    this.alreadyInLedger = 0,
    required this.total,
    required this.sourceName,
    required this.sourceId,
    this.startDate,
    this.endDate,
  });

  /// Rows that are now in the Transactions screen and were not before.
  ///
  /// It used to count rows recorded against the *source*, so importing a
  /// statement into a second source reported every row as imported while the
  /// ledger — deduplicated per wallet — gained nothing.
  final int imported;

  /// Rows this source had already imported.
  final int duplicatesSkipped;

  /// Rows new to this source but already in the ledger, typically from the
  /// same statement imported under another source. Recorded, not added twice.
  final int alreadyInLedger;
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

  /// The most recently started import — what [cancelImport] cancels.
  _ImportRun? _latest;

  /// Stream of raw AI response tokens emitted during Tier 1 Ollama parsing.
  /// Subscribe while an import is running to show live model output.
  Stream<String> get importTokenStream => _tokenController.stream;

  /// Cancels the most recently started import. Prefer passing an
  /// [ImportCancelToken] and cancelling that: it cannot reach the wrong one.
  void cancelImport() => _latest?.token.cancel();

  /// The import the current code is running for.
  ///
  /// Each import runs in a zone carrying its own [_ImportRun], so everything
  /// it awaits sees its own cancel flag and consent answers. They used to be
  /// fields on this singleton: starting a second import reset the first's
  /// cancel flag, so a cancelled import could carry on and upload the file.
  _ImportRun get _run =>
      Zone.current[#_importRun] as _ImportRun? ?? _ImportRun.none;

  /// Runs [body] as a new import.
  Future<ImportResult> _asNewRun(
    ImportCancelToken? token,
    Future<ImportResult> Function() body,
  ) {
    final run = _ImportRun(token ?? ImportCancelToken());
    _latest = run;
    return runZoned(body, zoneValues: {#_importRun: run});
  }

  void _checkCancelled() {
    if (_run.token.isCancelled) throw const ImportCancelledException();
  }

  // ── Off-device consent ───────────────────────────────────────────────────
  //
  // The AI tier is tried FIRST for every statement, and with a hosted provider
  // selected that means the raw file — account numbers, balances, every line
  // item — is uploaded to a third party before any local parsing is attempted.
  // That is more sensitive than anything the chat screen sends, and until this
  // gate existed nothing on the import screens said it happened at all.
  //
  // A private backend needs no gate: nothing leaves the device.

  /// Whether the user has already agreed to let the active provider's
  /// recipient read their statements. Always true for a private backend.
  Future<bool> offDeviceImportAllowed() async {
    if (!ollama.sendsDataOffDevice) return true;
    final row =
        await (db.select(db.appSettings)..where(
          (t) => t.key.equals(
            AppConstants.aiImportConsentKey(ollama.activeProvider.key),
          ),
        )).getSingleOrNull();
    final scope = ollama.activeConsentScope;
    // 'true' is how a consent was stored before it named its server. It still
    // stands for a hosted provider, whose endpoint cannot change; for one
    // whose URL is the user's, it is asked again.
    return row?.value == scope || (row?.value == 'true' && scope == 'hosted');
  }

  /// Records the user's answer for the active provider — and, for one whose
  /// server the user chose, for that server — so they are asked once rather
  /// than on every import.
  Future<void> setOffDeviceImportAllowed(bool allowed) async {
    if (!ollama.sendsDataOffDevice) return;
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.aiImportConsentKey(ollama.activeProvider.key),
            value: allowed ? ollama.activeConsentScope : 'false',
          ),
        );
  }

  /// Every provider currently allowed to read imported statements.
  ///
  /// Consent is stored per provider, so this can name more than the active
  /// one: agreeing for Claude and later switching to ChatGPT leaves Claude's
  /// answer in place for when the user switches back.
  Future<List<AiProvider>> providersAllowedToReadImports() async {
    final rows =
        await (db.select(db.appSettings)
          ..where((t) => t.key.isIn(_consentKeys.keys))).get();
    return [
      for (final r in rows)
        if (r.value.isNotEmpty && r.value != 'false') _consentKeys[r.key]!,
    ]..sort((a, b) => a.index.compareTo(b.index));
  }

  /// Withdraws every stored consent, so the next import that would upload a
  /// file asks first again.
  Future<void> revokeOffDeviceImportConsent() async {
    await (db.delete(db.appSettings)
      ..where((t) => t.key.isIn(_consentKeys.keys))).go();
  }

  /// Every provider's consent key. Matched exactly rather than by a `LIKE`
  /// prefix, in which `_` is a wildcard.
  static final _consentKeys = {
    for (final p in AiProvider.values)
      AppConstants.aiImportConsentKey(p.key): p,
  };

  /// May the AI tier run for this file?
  ///
  /// Private backend: yes. Otherwise the stored answer, or [onOffDeviceConsent]
  /// is asked. With no callback and no stored consent the answer is no — a
  /// caller that cannot ask must not send.
  ///
  /// A yes from the dialog is not stored here. It used to be, at the tap, so
  /// cancelling the import a second later — or the import failing — still
  /// left every future import uploading without asking. It is remembered by
  /// [_finishImport] once the import has actually completed.
  Future<bool> _aiTierPermitted(
    Future<bool> Function(String recipient)? onOffDeviceConsent,
  ) async {
    if (!ollama.sendsDataOffDevice) return true;
    final run = _run;
    if (run.consent != null) return run.consent!;
    if (await offDeviceImportAllowed()) return run.consent = true;
    final recipient = ollama.activeDataRecipient;
    if (onOffDeviceConsent == null || recipient == null) {
      return run.consent = false;
    }
    final granted = await onOffDeviceConsent(recipient);
    // Answered after a cancel: the dialog may still have been up when the
    // user left the screen, and a yes then must not start an upload.
    _checkCancelled();
    run.rememberConsent = granted;
    return run.consent = granted;
  }

  /// Whether the active backend can read a statement now.
  ///
  /// The on-device backends have no model to choose — `selectedModel` is null
  /// for them by design — so requiring one meant Apple Intelligence and Gemini
  /// Nano were never used for an import at all.
  Future<bool> _aiReady() async =>
      await ollama.isAvailable() &&
      (ollama.activeProvider.isOnDevice ||
          (ollama.selectedModel?.isNotEmpty ?? false));

  /// Called immediately before an AI tier hands the file to the backend.
  void _markSending() {
    _checkCancelled();
    if (ollama.sendsDataOffDevice) _run.sent = true;
  }

  /// Completes an import that ran to the end without being cancelled:
  /// remembers a consent given during it, and records who read the file.
  Future<ImportResult> _finishImport(ImportResult result) async {
    if (_run.rememberConsent) await setOffDeviceImportAllowed(true);
    final aiTier =
        result.tierUsed == ImportTier.ollama ||
        result.tierUsed == ImportTier.image;
    return result.withProvenance(
      sentTo: _run.sent ? ollama.activeDataRecipient : null,
      aiInputTruncatedAt: aiTier ? _run.truncatedAt : null,
      aiLabel: aiTier ? ollama.activeProvider.label : null,
    );
  }

  // ── Source currency ──────────────────────────────────────────────────────

  /// The currency the user said this account is denominated in
  /// (`ImportSourceSetupScreen`). Every parsed row inherits it unless the file
  /// itself states otherwise, which only the AI tiers can do.
  ///
  /// Every parse path used to hardcode `'USD'`, so the per-source choice was
  /// collected and then thrown away.
  Future<String> _sourceCurrency(int sourceId) async {
    final source =
        await (db.select(db.importSources)
          ..where((t) => t.id.equals(sourceId))).getSingleOrNull();
    return _normaliseCurrency(source?.currency);
  }

  /// The currency a model gave a row — only if [sourceText] itself names it,
  /// by code or by an unambiguous symbol; otherwise the account's.
  ///
  /// The model's answer used to be taken as given, so a model that labelled
  /// every row `USD` out of habit redenominated a sterling account, and a
  /// made-up code was stored as a currency.
  static String _modelRowCurrency(
    String? code,
    String fallback,
    String sourceText,
  ) {
    final claimed = code?.trim().toUpperCase() ?? '';
    if (claimed.isEmpty || claimed == fallback) return fallback;
    if (!RegExp(r'^[A-Z]{3,4}$').hasMatch(claimed)) return fallback;
    const symbols = {'EUR': '€', 'GBP': '£', 'BTC': '₿', 'JPY': '¥'};
    final named =
        RegExp('(?<![A-Za-z])$claimed(?![A-Za-z])').hasMatch(sourceText) ||
        (symbols[claimed] != null && sourceText.contains(symbols[claimed]!));
    return named ? claimed : fallback;
  }

  /// [code] if it is usable, else [fallback]. A model that omits the currency
  /// field, or reports one for a line it could not read, must not silently
  /// redenominate the account.
  static String _normaliseCurrency(String? code, [String fallback = 'USD']) {
    final trimmed = code?.trim().toUpperCase();
    return (trimmed == null || trimmed.isEmpty) ? fallback : trimmed;
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
    Future<bool> Function(String recipient)? onOffDeviceConsent,
    ImportCancelToken? cancelToken,
  }) => _asNewRun(cancelToken, () async {
    final lname = fileName.toLowerCase();
    // Anything that is not a PDF is read as delimited text: a .txt or .tsv
    // export goes the same way as a .csv.
    final fileType =
        lname.endsWith('.pdf') ? ImportFileType.pdf : ImportFileType.csv;

    ImportResult result;
    if (fileType == ImportFileType.pdf) {
      result = await _handlePdf(
        filePath,
        fileName,
        sourceId,
        onStageChange: onStageChange,
        onOffDeviceConsent: onOffDeviceConsent,
      );
    } else {
      result = await _handleCsv(
        filePath,
        fileName,
        sourceId,
        onStageChange: onStageChange,
        onOffDeviceConsent: onOffDeviceConsent,
      );
    }

    await prepareForReview(result.transactions, sourceId);
    return _finishImport(result);
  });

  /// Entry point for image import (camera or photo library).
  /// Sends the image to the active AI provider using the vision API and parses
  /// the returned JSON into [ParsedTransaction]s.
  Future<ImportResult> importImage({
    required String imagePath,
    required int sourceId,
    void Function(String stage)? onStageChange,
    Future<bool> Function(String recipient)? onOffDeviceConsent,
    ImportCancelToken? cancelToken,
  }) => _asNewRun(cancelToken, () async {
    final fileName =
        imagePath.contains('/')
            ? imagePath.split('/').last
            : imagePath.split('\\').last;
    final result = await _handleImage(
      imagePath,
      fileName,
      sourceId,
      onStageChange: onStageChange,
      onOffDeviceConsent: onOffDeviceConsent,
    );
    await prepareForReview(result.transactions, sourceId);
    return _finishImport(result);
  });

  /// Reads a CSV file and returns an [ImportResult] ready for the manual
  /// column mapper screen. Used when falling back from a timeout.
  Future<ImportResult> readCsvForManualMapping(
    String filePath,
    String fileName,
  ) async {
    try {
      final content = await File(filePath).readAsString();
      final allRows = _mappableRows(content);
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
        transactions: [],
        fileType: ImportFileType.csv,
        fileName: fileName,
      );
    }
  }

  // ── PDF flow ─────────────────────────────────────────────────────────────

  Future<ImportResult> _handlePdf(
    String filePath,
    String fileName,
    int sourceId, {
    void Function(String)? onStageChange,
    Future<bool> Function(String recipient)? onOffDeviceConsent,
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

    final currency = await _sourceCurrency(sourceId);
    final ollamaReady = await _aiReady();
    _checkCancelled();

    // Declining falls through to the same heuristic path as "no AI configured",
    // so the statement is still read — just locally.
    final aiPermitted =
        ollamaReady && await _aiTierPermitted(onOffDeviceConsent);
    _checkCancelled();

    if (!aiPermitted) {
      onStageChange?.call('Attempting heuristic detection…');
      await Future.delayed(const Duration(milliseconds: 60));
      final heuristicTxns = _parseTransactionsFromPdfText(text, currency);
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
        pdfAiNotReady: !ollamaReady,
        aiConsentDeclined: ollamaReady,
      );
    }

    _markSending();
    final txns = await parseWithOllama(
      text,
      fallbackCurrency: currency,
      onStageChange: onStageChange,
    );
    _checkCancelled();

    // The AI found nothing — or failed. The heuristic reader is what runs with
    // no AI at all; it used to be skipped here, so a PDF it could have read
    // came back empty just because an AI had been tried first.
    if (txns == null || txns.isEmpty) {
      onStageChange?.call('Attempting heuristic detection…');
      final heuristicTxns = _parseTransactionsFromPdfText(text, currency);
      if (heuristicTxns.length >= 3) {
        return ImportResult(
          transactions: heuristicTxns,
          tierUsed: ImportTier.pdfHeuristic,
          fileType: ImportFileType.pdf,
          fileName: fileName,
        );
      }
    }

    return ImportResult(
      transactions: txns ?? [],
      tierUsed: txns != null && txns.isNotEmpty ? ImportTier.ollama : null,
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
    Future<bool> Function(String recipient)? onOffDeviceConsent,
  }) async {
    onStageChange?.call('Preparing image…');
    await Future.delayed(const Duration(milliseconds: 60));
    _checkCancelled();

    // Checked before asking for consent: there is no point asking to send a
    // photo to a backend that will then refuse it.
    if (!ollama.canReadImages) {
      return ImportResult(
        transactions: [],
        fileType: ImportFileType.image,
        fileName: fileName,
        errorMessage:
            '${ollama.backend.displayName} cannot read images. '
            'Switch to Ollama, LM Studio or a hosted model in Settings → AI '
            'to import from a photo.',
      );
    }

    // Reading a photo of a statement has no local fallback — it is the model or
    // nothing. Ask before the image is encoded, not after.
    if (!await _aiTierPermitted(onOffDeviceConsent)) {
      return ImportResult(
        transactions: [],
        fileType: ImportFileType.image,
        fileName: fileName,
        aiConsentDeclined: true,
      );
    }
    _checkCancelled();

    final fallbackCurrency = await _sourceCurrency(sourceId);

    // Downscaled before encoding. A phone camera photo is 3–5 MB, which
    // base64 inflates by a third, and every hosted provider rejects it:
    // Anthropic caps an image at 5 MB and ~1,568 px on the long edge, OpenAI
    // caps the whole request at 20 MB. The user waited through the upload and
    // then got the provider's raw 400 back.
    final original = await File(imagePath).readAsBytes();
    final scaled = await _downscaleForVision(original);
    final base64Image = base64Encode(scaled.bytes);
    final mimeType = scaled.mimeType;
    _checkCancelled();

    const prompt =
        '''You are a financial data extraction assistant. This image shows a bank statement, credit card statement, or financial document. Extract every transaction you can see and return them as a JSON array.

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
    _run.token._attach(client);

    try {
      onStageChange?.call(
        'Sending to ${ollama.selectedModel ?? ollama.activeProvider.label}…',
      );
      await Future.delayed(const Duration(milliseconds: 60));
      onStageChange?.call('AI is reading your statement…');

      final buffer = StringBuffer();
      var tokenCount = 0;
      _markSending();
      await for (final token in ollama.chatWithImage(
        prompt,
        base64Image,
        mimeType: mimeType,
        client: client,
      )) {
        if (_run.token.isCancelled) break;
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

      final parsed =
          jsonArray
              .map((item) {
                try {
                  final map = item as Map<String, dynamic>;
                  final date = DateTime.tryParse(
                    (map['date'] as String?) ?? '',
                  );
                  if (date == null) return null;
                  final amount = (map['amount'] as num?)?.toDouble();
                  if (amount == null) return null;
                  final direction =
                      ((map['direction'] as String?) ?? 'debit').toLowerCase();
                  final description = (map['description'] as String?) ?? '';
                  // A photo gives nothing to check the model's code against,
                  // so the account's own currency stands.
                  final rowCurrency = fallbackCurrency;
                  return _categorised(
                    date: date,
                    amount: amount.abs(),
                    direction: direction == 'credit' ? 'credit' : 'debit',
                    description: description,
                    currency: rowCurrency,
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
    } on InferenceException catch (e) {
      // The backend's own explanation — a rejected key, an image too large —
      // is worth more than the generic advice the preview would otherwise
      // show. It used to be swallowed by the catch-all below.
      _checkCancelled();
      return ImportResult(
        transactions: [],
        fileType: ImportFileType.image,
        fileName: fileName,
        isPdfNoAi: true,
        errorMessage: e.message,
      );
    } catch (_) {
      _checkCancelled();
      return ImportResult(
        transactions: [],
        fileType: ImportFileType.image,
        fileName: fileName,
        isPdfNoAi: true,
      );
    } finally {
      _run.token._attach(null);
      client.close();
    }
  }

  // ── CSV flow ─────────────────────────────────────────────────────────────

  Future<ImportResult> _handleCsv(
    String filePath,
    String fileName,
    int sourceId, {
    void Function(String)? onStageChange,
    Future<bool> Function(String recipient)? onOffDeviceConsent,
  }) async {
    onStageChange?.call('Reading your statement…');
    await Future.delayed(const Duration(milliseconds: 60));
    _checkCancelled();

    final String content;
    try {
      content = await _readTextFile(filePath);
    } catch (_) {
      return ImportResult(
        transactions: [],
        fileType: ImportFileType.csv,
        fileName: fileName,
      );
    }
    _checkCancelled();

    final allRows = _parseCsvRows(content);
    if (allRows.isEmpty) {
      return ImportResult(
        transactions: [],
        fileType: ImportFileType.csv,
        fileName: fileName,
      );
    }

    // --- Check for a saved column mapping on this source ---
    final source =
        await (db.select(db.importSources)
          ..where((t) => t.id.equals(sourceId))).getSingleOrNull();
    _checkCancelled();

    final currency = _normaliseCurrency(source?.currency);

    if (source?.columnMapping != null) {
      try {
        final mapping = ColumnMapping.fromJson(
          jsonDecode(source!.columnMapping!) as Map<String, dynamic>,
        );
        final txns = await parseWithMapping(
          content,
          mapping,
          currency: currency,
        );
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

    // --- Tier 1: AI ---
    //
    // Asked before the file is read by anyone else. A CSV has the rule-based
    // tier to fall back on, so declining costs the user nothing but a slightly
    // worse parse.
    final ollamaReady = await _aiReady();
    _checkCancelled();

    if (ollamaReady && await _aiTierPermitted(onOffDeviceConsent)) {
      _markSending();
      final txns = await parseWithOllama(
        content,
        fallbackCurrency: currency,
        onStageChange: onStageChange,
      );
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
    final txns = await parseWithRules(
      content,
      currency: currency,
      sourceType: source?.type,
    );
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
    final mappable = _mappableRows(content);
    return ImportResult(
      transactions: [],
      needsManualMapping: true,
      fileType: ImportFileType.csv,
      fileName: fileName,
      rawCsvContent: content,
      csvRows: mappable,
      csvHeaders: mappable.isNotEmpty ? mappable[0] : const [],
    );
  }

  /// Longest edge a vision request should carry. Anthropic's own guidance;
  /// more pixels cost tokens without reading any better.
  static const _visionMaxEdge = 1568;

  /// Under the smallest limit any supported provider imposes, with room for
  /// base64's one-third overhead.
  static const _visionMaxBytes = 3 * 1024 * 1024;

  /// Decoded, resized and re-encoded through `dart:ui`, so there is no image
  /// package to add. Falls back to the original bytes if anything about the
  /// file defeats the decoder — better a request the provider might reject
  /// than an import that cannot start at all.
  Future<({Uint8List bytes, String mimeType})> _downscaleForVision(
    Uint8List original,
  ) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    // The smallest encode produced so far. Returning `original` when every
    // round came out too large — which is what this did — hands back the
    // multi-megabyte camera photo and throws away the 768px version it had
    // just made, which is the opposite of the point.
    Uint8List? best;

    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(original);
      // Decoded once, not once per round.
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final longest =
          descriptor.width > descriptor.height
              ? descriptor.width
              : descriptor.height;

      for (final maxEdge in const [_visionMaxEdge, 1024, 768]) {
        if (longest <= maxEdge && original.length <= _visionMaxBytes) {
          return (bytes: original, mimeType: _mimeTypeOf(original));
        }

        final scale = maxEdge / longest;
        ui.Codec? codec;
        ui.FrameInfo? frame;
        try {
          codec = await descriptor.instantiateCodec(
            targetWidth: (descriptor.width * scale).round().clamp(1, maxEdge),
            targetHeight: (descriptor.height * scale).round().clamp(1, maxEdge),
          );
          frame = await codec.getNextFrame();
          final encoded = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (encoded == null) break;

          final bytes = encoded.buffer.asUint8List();
          if (best == null || bytes.length < best.length) best = bytes;
          if (bytes.length <= _visionMaxBytes) {
            return (bytes: bytes, mimeType: 'image/png');
          }
          // Still too big: round again at a smaller edge.
        } finally {
          frame?.image.dispose();
          codec?.dispose();
        }
      }
    } catch (_) {
      // Fall through to whatever is in hand.
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }

    if (best != null) return (bytes: best, mimeType: 'image/png');
    return (bytes: original, mimeType: _mimeTypeOf(original));
  }

  /// From the file's own magic bytes rather than its extension, which is
  /// frequently wrong for a photo picked out of a gallery.
  static String _mimeTypeOf(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  // ── Tier 1: Ollama ────────────────────────────────────────────────────────

  Future<List<ParsedTransaction>?> parseWithOllama(
    String content, {
    required String fallbackCurrency,
    void Function(String)? onStageChange,
  }) async {
    final client = http.Client();
    _run.token._attach(client);

    try {
      const maxLen = 100000;
      final truncated =
          content.length > maxLen ? content.substring(0, maxLen) : content;
      if (truncated.length < content.length) _run.truncatedAt = maxLen;

      const prefix =
          '''You are a financial data parser. Extract every transaction from this bank/exchange statement and return them as a JSON array.

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

      onStageChange?.call(
        'Sending to ${ollama.selectedModel ?? ollama.activeProvider.label} for analysis…',
      );
      await Future.delayed(const Duration(milliseconds: 60));
      onStageChange?.call('AI is thinking…');

      final buffer = StringBuffer();
      var tokenCount = 0;
      await for (final token in ollama.chat(messages, client: client)) {
        if (_run.token.isCancelled) break;
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

      final parsed =
          jsonArray
              .map((item) {
                try {
                  final map = item as Map<String, dynamic>;
                  final date = DateTime.tryParse(
                    (map['date'] as String?) ?? '',
                  );
                  if (date == null) return null;
                  final amount = (map['amount'] as num?)?.toDouble();
                  if (amount == null) return null;
                  final direction =
                      ((map['direction'] as String?) ?? 'debit').toLowerCase();
                  final description = (map['description'] as String?) ?? '';
                  final rowCurrency = _modelRowCurrency(
                    map['currency'] as String?,
                    fallbackCurrency,
                    content,
                  );
                  return _categorised(
                    date: date,
                    amount: amount.abs(),
                    direction: direction == 'credit' ? 'credit' : 'debit',
                    description: description,
                    currency: rowCurrency,
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
      _checkCancelled();
      return null;
    } finally {
      _run.token._attach(null);
      client.close();
    }
  }

  // ── Tier 2: Rule-based CSV parsing ───────────────────────────────────────

  /// [sourceType] is the account's type (`credit_card`, `bank`, …), which
  /// decides how a signed amount column is read — see [_parseRowsGeneric].
  Future<List<ParsedTransaction>?> parseWithRules(
    String csvContent, {
    required String currency,
    String? sourceType,
  }) async {
    final parsedRows = _parseCsvRows(csvContent);
    if (parsedRows.length < 2) return null;

    // Many exports open with a title, an account number or a balance summary
    // before the real header. Reading row 0 as the header found no columns in
    // any of them, so they all fell through to manual mapping.
    final headerRow = _findHeaderRow(parsedRows);
    final allRows = headerRow == 0 ? parsedRows : parsedRows.sublist(headerRow);
    if (allRows.length < 2) return null;

    final headers = _normaliseHeaders(allRows[0]);

    // Try institution profile first
    final profile = InstitutionProfiles.detect(headers);
    if (profile != null) {
      return _parseWithProfile(allRows, headers, profile, currency);
    }

    int? dateCol, amountCol, debitCol, creditCol, descCol;
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (dateCol == null && _dateNames.contains(h)) dateCol = i;
      if (amountCol == null && _amountNames.contains(h)) amountCol = i;
      if (debitCol == null && _debitNames.contains(h)) debitCol = i;
      if (creditCol == null && _creditNames.contains(h)) creditCol = i;
      if (descCol == null && _descNames.contains(h)) descCol = i;
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
      currency: currency,
      chargesMaySignPositive: sourceType == 'credit_card',
    );
  }

  static const _dateNames = {
    'date',
    'transaction date',
    'posted date',
    'posting date',
    'trans date',
    'value date',
    'trade date',
  };
  static const _amountNames = {'amount', 'transaction amount', 'total'};
  static const _debitNames = {
    'debit',
    'withdrawals',
    'withdrawal',
    'debit amount',
    'charges',
    'out',
  };
  static const _creditNames = {
    'credit',
    'deposits',
    'deposit',
    'credit amount',
    'payments',
    'in',
  };
  static const _descNames = {
    'description',
    'memo',
    'narrative',
    'payee',
    'merchant',
    'details',
    'transaction description',
    'particulars',
    'name',
  };

  static List<String> _normaliseHeaders(List<String> row) =>
      row.map((h) => h.toLowerCase().trim().replaceAll('"', '')).toList();

  /// The index of the header row: the first of the opening rows that an
  /// institution profile recognises, or that names a date column and an
  /// amount column. Row 0 when none does, which is what a file with no
  /// header at all (a positional profile) needs.
  /// [csvContent]'s rows from the detected header row on — what the column
  /// mapper shows and what a mapping's column numbers refer to.
  ///
  /// The mapper used to take row 0 as the header, which for an export opening
  /// with a title or an account summary offered the title as the column names,
  /// and every mapped column was then read against the wrong rows.
  List<List<String>> _mappableRows(String csvContent) {
    final rows = _parseCsvRows(csvContent);
    if (rows.isEmpty) return rows;
    final header = _findHeaderRow(rows);
    return header == 0 ? rows : rows.sublist(header);
  }

  static int _findHeaderRow(List<List<String>> rows) {
    final limit = rows.length < 15 ? rows.length : 15;
    for (var i = 0; i < limit; i++) {
      final headers = _normaliseHeaders(rows[i]);
      if (InstitutionProfiles.detect(headers) != null) return i;
      final hasDate = headers.any(_dateNames.contains);
      final hasAmount =
          headers.any(_amountNames.contains) ||
          headers.any(_debitNames.contains) ||
          headers.any(_creditNames.contains);
      if (hasDate && hasAmount) return i;
    }
    return 0;
  }

  List<ParsedTransaction>? _parseWithProfile(
    List<List<String>> allRows,
    List<String> headers,
    InstitutionProfile profile,
    String currency,
  ) {
    int? dateCol, descCol, amountCol, debitCol, creditCol;
    int? column(String? header) {
      if (header == null) return null;
      final i = headers.indexOf(header);
      return i == -1 ? null : i;
    }

    if (profile.positional) {
      dateCol = profile.dateColumn;
      descCol = profile.descriptionColumn;
      amountCol = profile.amountColumn;
    } else {
      dateCol =
          profile.dateHeader != null
              ? headers.indexOf(profile.dateHeader!)
              : null;
      descCol =
          profile.descriptionHeader != null
              ? headers.indexOf(profile.descriptionHeader!)
              : null;
      amountCol =
          profile.amountHeader != null
              ? headers.indexOf(profile.amountHeader!)
              : null;
      debitCol =
          profile.debitHeader != null
              ? headers.indexOf(profile.debitHeader!)
              : null;
      creditCol =
          profile.creditHeader != null
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
      // The account's own currency unless the layout says which currency its
      // amount column is in. An exchange export's "Amount USD" is dollars
      // whatever the account holds: stamping it with the account's currency
      // read a $500 purchase in a BTC account as 500 BTC.
      currency: profile.amountCurrency ?? currency,
      currencyCol: column(profile.currencyHeader),
      typeCol: column(profile.typeHeader),
      creditTypes: profile.creditTypes,
      // Honoured at last: a positional profile (Wells Fargo) has no header
      // line, and skipping row 0 regardless dropped its first transaction.
      skipHeaderRow: profile.skipHeaderRow,
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
    bool skipHeaderRow = true,
    bool chargesMaySignPositive = false,
    int? currencyCol,
    int? typeCol,
    Set<String> creditTypes = const {},
  }) {
    if (dateCol == null) return null;

    // A positional profile (Wells Fargo) has no header line, so starting at 1
    // threw away its first transaction on every single import.
    final startRow = skipHeaderRow ? 1 : 0;
    if (allRows.length <= startRow) return null;

    final dateIndex = dateCol;
    final dataRows = allRows.skip(startRow);
    final dayFirst = _inferDayFirst(
      dataRows.where((r) => dateIndex < r.length).map((r) => r[dateIndex]),
    );
    final dots = _inferDotGrouping([
      for (final r in dataRows)
        for (final c in [amountCol, debitCol, creditCol])
          if (c != null && c < r.length) r[c],
    ]);
    double? amountOf(String raw) => _parseAmount(raw, dotGroupsThousands: dots);

    // A single amount column with no negative value in it is not signed,
    // whatever the header says: treating it as signed books every charge on a
    // credit-card export as income.
    final amountIndex = amountCol;
    final amountCells = [
      if (amountIndex != null)
        for (final r in dataRows)
          if (amountIndex < r.length) r[amountIndex],
    ];
    final values = amountCells.map(amountOf).whereType<double>();
    final negatives = values.where((v) => v < 0).length;
    final positives = values.where((v) => v > 0).length;
    final amountIsSigned = signedAmount && negatives > 0;

    // Which sign is money out. Negative, for a bank account. A card statement
    // is mostly charges, and issuers disagree on their sign — Chase writes a
    // purchase as -4.50, Amex as 4.50 with the payments negative — so for a
    // card the majority sign is the charges. Reading Amex as "negative is
    // money out" booked every purchase as income.
    final positiveIsDebit =
        amountIsSigned && chargesMaySignPositive && positives > negatives;

    // A column that marks some amounts CR and has no negatives is a UK card
    // statement: CR is a payment or refund and an unmarked figure is a
    // charge. ('12.50 DR' parses as negative, so a DR column is signed.)
    final crMarked = !amountIsSigned && amountCells.any(_crSuffix.hasMatch);

    final result = <ParsedTransaction>[];
    for (int i = startRow; i < allRows.length; i++) {
      final row = allRows[i];
      if (row.every((e) => e.trim().isEmpty)) continue;

      final date =
          dateCol < row.length
              ? _parseDate(row[dateCol], dayFirst: dayFirst)
              : null;
      if (date == null) continue;

      final description =
          (descCol != null && descCol < row.length) ? row[descCol].trim() : '';
      if (description.isEmpty) continue;

      double? amount;
      String direction;

      if (amountCol != null && amountCol < row.length) {
        final raw = amountOf(row[amountCol]);
        if (raw == null) continue;
        amount = raw.abs();
        final type =
            (typeCol != null && typeCol < row.length)
                ? row[typeCol].trim().toLowerCase()
                : null;
        if (amountIsSigned) {
          direction = (raw < 0) != positiveIsDebit ? 'debit' : 'credit';
        } else if (type != null && type.isNotEmpty) {
          direction = creditTypes.contains(type) ? 'credit' : 'debit';
        } else if (crMarked) {
          direction = _crSuffix.hasMatch(row[amountCol]) ? 'credit' : 'debit';
        } else {
          direction = _unsignedDirection(description);
        }
      } else {
        final dAmt =
            (debitCol != null && debitCol < row.length)
                ? amountOf(row[debitCol])
                : null;
        final cAmt =
            (creditCol != null && creditCol < row.length)
                ? amountOf(row[creditCol])
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

      result.add(
        _categorised(
          date: date,
          amount: amount,
          direction: direction,
          description: description,
          currency: _rowCurrency(row, currencyCol, currency),
        ),
      );
    }
    return result.isEmpty ? null : result;
  }

  static final _crSuffix = RegExp(r'\s*CR\.?$', caseSensitive: false);
  static final _balanceLine = RegExp(
    r'\b(?:opening|closing|previous|new|start(?:ing)?|end(?:ing)?)\s+balance'
    r'|balance\s+(?:brought|carried)\s+forward|\bbalance\s+b/?f\b',
  );

  /// The direction of an amount when nothing in the file says which way the
  /// money went. Most such rows are spending; an unmistakable credit — a
  /// salary, a refund, interest — is the exception worth catching, or a
  /// deposits-only savings export reads as all spending.
  String _unsignedDirection(String description) =>
      matchCategory(description) == 'Income' ? 'credit' : 'debit';
  static final _currencyCode = RegExp(r'^[A-Z]{3,4}$');

  /// The currency named in [row]'s [col], if it names one, else [fallback].
  static String _rowCurrency(List<String> row, int? col, String fallback) {
    if (col == null || col >= row.length) return fallback;
    final code = row[col].trim().toUpperCase();
    return _currencyCode.hasMatch(code) ? code : fallback;
  }

  // ── Tier 3: Manual column mapping ─────────────────────────────────────────

  Future<List<ParsedTransaction>?> parseWithMapping(
    String csvContent,
    ColumnMapping mapping, {
    String? currency,
    int? sourceId,
  }) async {
    assert(
      currency != null || sourceId != null,
      'parseWithMapping needs the account currency or the source to read it from',
    );
    final rowCurrency = currency ?? await _sourceCurrency(sourceId!);
    final allRows = _mappableRows(csvContent);
    if (allRows.length < 2) return null;

    final dots = _inferDotGrouping([
      for (final r in allRows.skip(1))
        for (final c in [
          mapping.amountColumn,
          mapping.debitColumn,
          mapping.creditColumn,
        ])
          if (c != null && c < r.length) r[c],
    ]);
    double? amountOf(String raw) => _parseAmount(raw, dotGroupsThousands: dots);

    final amountIndex = mapping.amountColumn;
    final mappingAmountIsSigned =
        amountIndex == null ||
        allRows
            .skip(1)
            .any(
              (r) =>
                  amountIndex < r.length && (amountOf(r[amountIndex]) ?? 0) < 0,
            );

    final result = <ParsedTransaction>[];
    for (int i = 1; i < allRows.length; i++) {
      final row = allRows[i];
      if (row.every((e) => e.trim().isEmpty)) continue;

      DateTime? date;
      if (mapping.dateColumn != null && mapping.dateColumn! < row.length) {
        date = _parseDateWithFormat(
          row[mapping.dateColumn!],
          mapping.dateFormat,
        );
      }
      if (date == null) continue;

      final description =
          (mapping.descriptionColumn != null &&
                  mapping.descriptionColumn! < row.length)
              ? row[mapping.descriptionColumn!].trim()
              : '';
      if (description.isEmpty) continue;

      double? amount;
      String direction;

      if (mapping.amountColumn != null && mapping.amountColumn! < row.length) {
        final raw = amountOf(row[mapping.amountColumn!]);
        if (raw == null) continue;
        amount = raw.abs();
        // Same rule as the rules tier: a single amount column with no
        // negative value in it is not signed, whatever the header says.
        // Deriving the direction from the sign alone booked every charge on a
        // credit-card export as income — and this is the tier a saved mapping
        // uses, so it was the *first* thing tried on every later import of
        // that source.
        direction =
            mappingAmountIsSigned ? (raw < 0 ? 'debit' : 'credit') : 'debit';
      } else {
        final dAmt =
            (mapping.debitColumn != null && mapping.debitColumn! < row.length)
                ? amountOf(row[mapping.debitColumn!])
                : null;
        final cAmt =
            (mapping.creditColumn != null && mapping.creditColumn! < row.length)
                ? amountOf(row[mapping.creditColumn!])
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

      result.add(
        _categorised(
          date: date,
          amount: amount,
          direction: direction,
          description: description,
          currency: rowCurrency,
        ),
      );
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

  /// Writes the included rows into `importedTransactions` and the main
  /// `transactions` table.
  ///
  /// [btcPriceService] supplies the historical rate for each row's date, which
  /// is what makes a Bitcoin-denominated account storable: `amountFiat` is a
  /// money column the dashboard sums, so a 0.05 BTC deposit written there
  /// verbatim read as "$0.05". [btcPrice] is the spot rate, used only when a
  /// row's historical price cannot be resolved.
  Future<ImportSummary> saveTransactions({
    required List<ParsedTransaction> transactions,
    required int sourceId,
    required String sourceName,
    required BtcPriceService btcPriceService,
    double? btcPrice,
    void Function(int done, int total)? onPricingProgress,
  }) async {
    // FK for the main transactions table. Prefer a manual wallet: `wallets`
    // comes back unordered, so `first` could be an xpub wallet, which would
    // attribute bank-statement rows to a Bitcoin wallet and pollute the
    // dashboard's per-wallet breakdown.
    final wallets = await db.select(db.wallets).get();
    final walletId =
        (wallets.where((w) => w.type == 'manual').firstOrNull ??
                wallets.firstOrNull)
            ?.id;

    // Load all existing hashes for this source to detect duplicates
    final existingRows =
        await (db.select(db.importedTransactions)
          ..where((t) => t.sourceId.equals(sourceId))).get();
    final existingHashes = {for (final r in existingRows) r.importHash};

    int imported = 0;
    int duplicatesSkipped = 0;
    int alreadyInLedger = 0;
    DateTime? startDate;
    DateTime? endDate;

    final toInsert = transactions.where((t) => t.include).toList();

    // ── Resolve historical prices up front, once per date ───────────────────
    //
    // Before the write transaction opens: `getHistoricalPrice` goes to the
    // network and writes its own cache rows, neither of which belongs inside a
    // held write lock.
    //
    // Priced in the row's own currency. A EUR account's sats were worked out
    // from the display currency's price — euros divided by a dollar price.
    // A Bitcoin row is valued in the display currency, as everywhere else.
    final displayCurrency = btcPriceService.currency;
    String priceCurrency(ParsedTransaction tx) =>
        _isBitcoinCurrency(tx.currency) || tx.currency.length != 3
            ? displayCurrency
            : tx.currency;
    final toPrice = <String, (DateTime, String)>{
      for (final tx in toInsert)
        '${_dayKey(tx.date)}|${priceCurrency(tx)}': (
          tx.date,
          priceCurrency(tx),
        ),
    };
    // One request per currency for the bulk of the days, where the server
    // allows it; then the per-day lookups, now mostly cache hits.
    final byCurrency = <String, List<DateTime>>{};
    for (final (date, currency) in toPrice.values) {
      (byCurrency[currency] ??= []).add(date);
    }
    for (final MapEntry(key: currency, value: dates) in byCurrency.entries) {
      await btcPriceService.prefetchHistoricalPrices(dates, currency);
    }
    final priceByDay = <String, double?>{};
    var priced = 0;
    for (final MapEntry(:key, value: (date, currency)) in toPrice.entries) {
      onPricingProgress?.call(priced++, toPrice.length);
      priceByDay[key] = await btcPriceService.getHistoricalPrice(
        date,
        currency,
      );
    }

    double? priceFor(ParsedTransaction tx) {
      final currency = priceCurrency(tx);
      final historical = priceByDay['${_dayKey(tx.date)}|$currency'];
      if (historical != null && historical > 0) return historical;
      // The live price is in the display currency, so it is no stand-in for
      // any other.
      return (currency == displayCurrency && btcPrice != null && btcPrice > 0)
          ? btcPrice
          : null;
    }

    // How many times each row has already appeared in this file, so that two
    // genuinely identical rows — two bus fares, same day, same amount — are
    // two transactions. Keyed as each hash is, below.
    final seenUnsigned = <String, int>{};
    final seenSigned = <String, int>{};
    int occurrence(Map<String, int> seen, String key) {
      final n = seen[key] ?? 0;
      seen[key] = n + 1;
      return n;
    }

    // ── One write transaction for the whole import ──────────────────────────
    //
    // Every committed statement fires `transactions.watchAll()`, which
    // main.dart turns into a budget re-check plus three full table selects, and
    // wakes every mounted StreamBuilder. Row by row, a 300-row import meant
    // hundreds of full scans and a multi-second freeze. Wrapping the loop also
    // means the two tables can no longer disagree if the app is killed
    // mid-import: either a row is in both or in neither.
    await db.transaction(() async {
      for (final tx in toInsert) {
        final cents = _toSmallestUnit(tx.amount, tx.currency);
        final hash = computeHash(
          sourceId,
          tx.date,
          cents,
          tx.rawDescription,
          occurrence: occurrence(
            seenUnsigned,
            '${tx.date.toIso8601String()}|$cents|${tx.rawDescription}',
          ),
        );

        if (existingHashes.contains(hash)) {
          duplicatesSkipped++;
          continue;
        }

        try {
          // `insertReturningOrNull` says whether a row was actually written;
          // `insert` with insertOrIgnore returns a rowid either way.
          final recorded = await db
              .into(db.importedTransactions)
              .insertReturningOrNull(
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
          if (recorded == null) {
            duplicatesSkipped++;
            continue;
          }
          if (walletId == null) imported++;
          // Explicit `!`: captured by the transaction closure, these no longer
          // promote on a null check.
          if (startDate == null || tx.date.isBefore(startDate!)) {
            startDate = tx.date;
          }
          if (endDate == null || tx.date.isAfter(endDate!)) endDate = tx.date;
        } catch (_) {
          duplicatesSkipped++;
          continue;
        }

        // Also write into the main transactions table so the Transactions screen
        // can display imported data alongside manual and xpub entries.
        if (walletId != null) {
          final isBitcoin = _isBitcoinCurrency(tx.currency);
          final price = priceFor(tx);
          // The signed amount in the account's own currency.
          final signedSource =
              tx.direction == 'credit' ? tx.amount : -tx.amount;

          final int amountSats;
          final double amountFiat;
          final String fiatCurrency;
          if (isBitcoin) {
            // `cents` is already sats for a BTC/SATS account. The fiat column is
            // derived from it, never a copy of the BTC figure — writing 0.05
            // there made the dashboard read a 0.05 BTC deposit as "$0.05".
            amountSats = tx.direction == 'credit' ? cents : -cents;
            amountFiat = price != null ? amountSats / 100000000 * price : 0.0;
            fiatCurrency = displayCurrency;
          } else {
            amountFiat = signedSource;
            fiatCurrency =
                tx.currency.length == 3 ? tx.currency : displayCurrency;
            amountSats =
                price != null ? (signedSource / price * 100000000).round() : 0;
          }
          // Hash the *signed* amount, and scope it to the import source.
          //
          // `tx.amount` is always positive, so a charge and its same-day refund
          // hashed identically and the refund was dropped by the unique index —
          // silently, because the insert is insertOrIgnore. The source salt
          // stops the same figure in two accounts colliding the same way: it
          // used to be the wallet's, but every source writes to the one manual
          // wallet, so that separated nothing. Re-importing into the same
          // source is caught by the source's own import hash first.
          final dedupHash = HashUtils.transactionDedupHash(
            date: tx.date,
            amount: signedSource,
            description: tx.rawDescription,
            salt: importDedupSalt(
              sourceId,
              occurrence(
                seenSigned,
                '${tx.date.toIso8601String()}|$signedSource|'
                '${tx.rawDescription}',
              ),
            ),
          );
          try {
            final added = await db
                .into(db.transactions)
                .insertReturningOrNull(
                  TransactionsCompanion.insert(
                    walletId: walletId,
                    date: tx.date,
                    description: tx.description,
                    amountFiat: amountFiat,
                    amountSats: amountSats,
                    fiatCurrency: fiatCurrency,
                    category: Value(tx.category),
                    source: 'csv',
                    isBitcoin: Value(isBitcoin),
                    dedupHash: dedupHash,
                  ),
                  mode: InsertMode.insertOrIgnore,
                );
            added == null ? alreadyInLedger++ : imported++;
          } catch (_) {
            // Unique constraint violation — already in the main table.
            alreadyInLedger++;
          }
        }
      }

      // Inside the same transaction: another few hundred statements, and a
      // half-written mapping set would mis-categorise the next import.
      await _saveDescriptionMappings(toInsert, sourceId);
    });

    return ImportSummary(
      imported: imported,
      duplicatesSkipped: duplicatesSkipped,
      alreadyInLedger: alreadyInLedger,
      total: toInsert.length,
      sourceName: sourceName,
      sourceId: sourceId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  // ── Description → Category mappings ─────────────────────────────────────

  /// Gets parsed rows ready for the preview, whichever tier read them: the
  /// keyword categories under the names the user has given them, then the
  /// categories learned from earlier imports of [sourceId].
  ///
  /// The column mapper's parse used to skip both.
  Future<void> prepareForReview(
    List<ParsedTransaction> transactions,
    int sourceId,
  ) async {
    if (transactions.isEmpty) return;
    await _applySystemCategoryNames(transactions);
    await _applyDescriptionMappings(transactions, sourceId);
  }

  /// The keyword categoriser names the built-in categories as they were
  /// seeded. A user who renamed "Food & Dining" to "Food" got imports filed
  /// under a name that no longer existed — invisible to the budget, the
  /// charts and the category list. `CategoryService.updateCategory` records
  /// each rename of a built-in category; this applies them.
  Future<void> _applySystemCategoryNames(
    List<ParsedTransaction> transactions,
  ) async {
    final renames =
        await (db.select(db.appSettings)..where(
          (t) => t.key.like('${AppConstants.systemCategoryNamePrefix}%'),
        )).get();
    if (renames.isEmpty) return;
    final current = {
      for (final r in renames)
        r.key.substring(AppConstants.systemCategoryNamePrefix.length): r.value,
    };
    for (final tx in transactions) {
      if (tx.categoryIsUserChosen) continue;
      final renamed = current[tx.category];
      if (renamed != null) tx.category = renamed;
    }
  }

  /// Pre-fills [transactions] categories from previously saved mappings for
  /// [sourceId].  Only overwrites the auto-category if a saved mapping exists.
  ///
  /// Keyed on the description as the file gives it. It was the description as
  /// the user had edited it in the preview, which the next file never
  /// contains, so tidying a merchant's name stopped its category being learned.
  /// Mappings stored under an edited description still match one.
  Future<void> _applyDescriptionMappings(
    List<ParsedTransaction> transactions,
    int sourceId,
  ) async {
    final rows =
        await (db.select(db.descriptionCategoryMappings)
          ..where((t) => t.sourceId.equals(sourceId))).get();
    if (rows.isEmpty) return;
    final map = {for (final r in rows) r.description: r.category};
    for (final tx in transactions) {
      final saved =
          map[tx.rawDescription.toLowerCase().trim()] ??
          map[tx.description.toLowerCase().trim()];
      if (saved != null) tx.setUserCategory(saved);
    }
  }

  /// Persists a description → category mapping for every included transaction
  /// that has a category set.  Uses delete-then-insert to upsert.
  /// Remembers description → category for the next import of this source.
  ///
  /// Collapsed in memory first, then written as one batch of upserts against
  /// the unique `(sourceId, description)` index. It used to delete and insert,
  /// awaited, once per row — four round-trips per line for a file that repeats
  /// the same merchant forty times, and the delete/insert pair was not atomic.
  Future<void> _saveDescriptionMappings(
    List<ParsedTransaction> transactions,
    int sourceId,
  ) async {
    final byDescription = <String, String>{};
    for (final tx in transactions) {
      if (!tx.include) continue;
      // Only what the user actually chose.
      //
      // Learning the fallback pinned every unrecognised merchant to 'Other'
      // for good, because the mapping is re-applied on every later import of
      // that source. Learning a *keyword guess* has the same effect one step
      // removed: a wrong guess is frozen into the source's mappings and
      // improving the keyword list changes nothing for it. Only a category the
      // user picked — or one they picked on an earlier import — is worth
      // persisting.
      if (!tx.categoryIsUserChosen) continue;
      final cat = tx.category;
      if (cat == null || cat.isEmpty) continue;
      final key = tx.rawDescription.toLowerCase().trim();
      if (key.isEmpty) continue;
      // Last one wins, matching the previous row-by-row behaviour.
      byDescription[key] = cat;
    }
    if (byDescription.isEmpty) return;

    await db.batch((b) {
      for (final entry in byDescription.entries) {
        b.insert(
          db.descriptionCategoryMappings,
          DescriptionCategoryMappingsCompanion.insert(
            description: entry.key,
            sourceId: sourceId,
            category: entry.value,
          ),
          onConflict: DoUpdate(
            (_) => DescriptionCategoryMappingsCompanion(
              category: Value(entry.value),
            ),
            target: [
              db.descriptionCategoryMappings.sourceId,
              db.descriptionCategoryMappings.description,
            ],
          ),
        );
      }
    });
  }

  // ── Save / update column mapping on a source ─────────────────────────────

  /// Forgets [sourceId]'s saved column layout, so its next import is read
  /// from scratch. A wrong saved layout was otherwise permanent: it is tried
  /// first on every import of the source.
  Future<void> clearColumnMapping(int sourceId) async {
    await (db.update(db.importSources)..where(
      (t) => t.id.equals(sourceId),
    )).write(const ImportSourcesCompanion(columnMapping: Value(null)));
  }

  Future<void> saveColumnMapping(int sourceId, ColumnMapping mapping) async {
    await (db.update(db.importSources)
      ..where((t) => t.id.equals(sourceId))).write(
      ImportSourcesCompanion(
        columnMapping: Value(jsonEncode(mapping.toJson())),
      ),
    );
  }

  // ── Source CRUD ───────────────────────────────────────────────────────────

  Stream<List<ImportSource>> watchSources() =>
      db.select(db.importSources).watch();

  Future<int> createSource({
    required String name,
    required String type,
    required String currency,
  }) => db
      .into(db.importSources)
      .insert(
        ImportSourcesCompanion.insert(
          name: name,
          type: type,
          currency: currency,
        ),
      );

  /// Deletes a source and everything that references it.
  ///
  /// All three in one transaction, children first. Two things were wrong
  /// before: `descriptionCategoryMappings` also references `importSources`
  /// and was not deleted, so once `PRAGMA foreign_keys` was turned on this
  /// threw `FOREIGN KEY constraint failed` — and because the deletes were not
  /// in a transaction, the source's imported history was already gone by the
  /// time it threw, leaving the source listed with its history destroyed.
  Future<void> deleteSource(int id) async {
    await db.transaction(() async {
      await (db.delete(db.descriptionCategoryMappings)
        ..where((t) => t.sourceId.equals(id))).go();
      await (db.delete(db.importedTransactions)
        ..where((t) => t.sourceId.equals(id))).go();
      await (db.delete(db.importSources)..where((t) => t.id.equals(id))).go();
    });
  }

  // ── Heuristic PDF parser (no-AI fallback) ────────────────────────────────

  /// The heuristic PDF tier on its own, for tests: extracting text from a real
  /// PDF is a separate concern with its own failure modes.
  @visibleForTesting
  List<ParsedTransaction> parsePdfText(
    String text, {
    String currency = 'USD',
  }) => _parseTransactionsFromPdfText(text, currency);

  /// Parses transactions from plain-text PDF content using pattern matching.
  /// Returns an empty list when fewer than 3 rows are found (low confidence).
  List<ParsedTransaction> _parseTransactionsFromPdfText(
    String text,
    String currency,
  ) {
    final lines = text.split(RegExp(r'\r?\n'));

    // Date patterns tried in order — take the first match per line.
    //
    // The numeric forms accept `/`, `-` and `.`: this tier had no dotted
    // pattern, so a German `01.02.2025` line matched nothing at all — and this
    // is the tier a user lands on when they decline off-device consent.
    final datePats = <RegExp>[
      RegExp(r'\d{4}-\d{2}-\d{2}'),
      RegExp(r'(?<![\d.])\d{1,2}[/.-]\d{1,2}[/.-]\d{4}(?!\d)'),
      RegExp(r'(?<![\d.])\d{1,2}[/.-]\d{1,2}[/.-]\d{2}(?![\d.])'),
      RegExp(
        r'\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\s+\d{4}',
        caseSensitive: false,
      ),
    ];

    // Matches currency amounts; requires a decimal, a thousands separator or
    // a currency prefix — avoids matching plain integers like years or
    // reference numbers. Both conventions are matched here (`1,234.56` and
    // `1.234,56`); which one a file uses is decided below, once, from all of
    // its amounts together.
    final amtPat = RegExp(
      r'[$£€]\d+(?:[.,]\d+)*' // $1,234.56 €1.234,56 £50
      r'|[-+]?\(?\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?\)?-?' // 1,234 or 1,234.56
      r'|[-+]?\(?\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?\)?-?' // 1.234 or 1.234,56
      r'|[-+]?\(?\d+[.,]\d{1,2}(?!\d)\)?-?', // 12.50 12,50 (12.50)
    );

    // Noise tokens stripped from descriptions.
    final noisePat = RegExp(
      r'\b(?:ACH|POS|REF#?\w*|TXN\w*)\b',
      caseSensitive: false,
    );

    // The day/month order and the amount convention are properties of the
    // statement, not of a line, so both are settled once from the whole text
    // — as the CSV tiers do. This tier used to call `_parseDate` with the
    // default month-first, so a UK `04/03/2025` was booked as 3 April.
    final dayFirst = _inferDayFirst([
      for (final line in lines)
        for (final pat in datePats.skip(1).take(2))
          ...pat.allMatches(line).map((m) => m.group(0)!),
    ]);
    final dots = _inferDotGrouping([
      for (final line in lines)
        ...amtPat.allMatches(line).map((m) => m.group(0)!),
    ]);
    double? amountOf(String raw) => _parseAmount(raw, dotGroupsThousands: dots);

    // Set by a column header line, when there is one; null until then.
    String? columnCtx;
    // Whether the statement has a running-balance column, and the balance
    // after the last line read. With one, each line's direction is whichever
    // way its amount moves the balance — the only reliable signal in an
    // "Amount  Balance" layout, where both numbers are positive.
    var hasBalanceColumn = false;
    double? balance;
    final result = <ParsedTransaction>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();

      // Find the first date match on this line.
      RegExpMatch? dateMatch;
      for (final pat in datePats) {
        dateMatch = pat.firstMatch(line);
        if (dateMatch != null) break;
      }

      // A line with no date may be a column header; update the context from
      // those only. Reading it from every line flipped the rest of the
      // statement to "credit" at the first "CREDIT INTEREST" transaction.
      if (dateMatch == null) {
        final hasDebit =
            lower.contains('withdrawal') || lower.contains('debit');
        final hasCredit = lower.contains('deposit') || lower.contains('credit');
        if (hasDebit && !hasCredit) columnCtx = 'debit';
        if (hasCredit && !hasDebit) columnCtx = 'credit';
        if (lower.contains('balance')) {
          hasBalanceColumn = true;
          // "Balance brought forward  1,500.00" seeds the running balance.
          final amounts = amtPat.allMatches(line).toList();
          if (amounts.length == 1) balance = amountOf(amounts.first.group(0)!);
        }
        continue;
      }

      final date = _parseDate(dateMatch.group(0)!, dayFirst: dayFirst);
      if (date == null) continue;

      // Find amounts outside the date region.
      final amtMatches =
          amtPat
              .allMatches(line)
              .where(
                (m) => m.end <= dateMatch!.start || m.start >= dateMatch.end,
              )
              .toList();

      // An opening or closing balance line is not a transaction, but an
      // opening one gives the first line something to be measured against.
      if (_balanceLine.hasMatch(lower)) {
        if (amtMatches.length == 1) {
          balance = amountOf(amtMatches.first.group(0)!);
        }
        continue;
      }

      double amount;
      String direction;

      if (amtMatches.isEmpty) {
        // Look ahead up to 2 lines for an amount.
        double? lookAhead;
        for (int j = 1; j <= 2 && (i + j) < lines.length; j++) {
          for (final m in amtPat.allMatches(lines[i + j].trim())) {
            final p = amountOf(m.group(0)!);
            if (p != null && p.abs() > 0.001) {
              lookAhead = p;
              break;
            }
          }
          if (lookAhead != null) break;
        }
        if (lookAhead == null) continue;
        amount = lookAhead.abs();
        direction =
            lookAhead < 0 ? 'debit' : columnCtx ?? _unsignedDirection(line);
      } else if (amtMatches.length >= 2 &&
          hasBalanceColumn &&
          amountOf(amtMatches.first.group(0)!) != null &&
          amountOf(amtMatches.last.group(0)!) != null) {
        // Amount, then the running balance. Read the direction off the
        // balance: assuming "first column is withdrawals" booked every
        // salary in such a statement as spending.
        final a = amountOf(amtMatches.first.group(0)!)!;
        final after = amountOf(amtMatches.last.group(0)!)!;
        if (a.abs() < 0.001) continue;
        amount = a.abs();
        final before = balance;
        balance = after;
        if (a < 0) {
          direction = 'debit';
        } else if (before != null && (before - amount - after).abs() < 0.005) {
          direction = 'debit';
        } else if (before != null && (before + amount - after).abs() < 0.005) {
          direction = 'credit';
        } else {
          // The first line, with no opening balance to measure from.
          direction = _unsignedDirection(line);
        }
      } else if (amtMatches.length >= 2) {
        // Two-column format: first column = withdrawals, second = deposits.
        // Whichever is non-zero is the transaction amount.
        final a = amountOf(amtMatches[0].group(0)!);
        final b = amountOf(amtMatches[1].group(0)!);
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
        final p = amountOf(amtMatches[0].group(0)!);
        if (p == null || p.abs() < 0.001) continue;
        amount = p.abs();
        direction = p < 0 ? 'debit' : columnCtx ?? _unsignedDirection(line);
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

      result.add(
        _categorised(
          date: date,
          amount: amount,
          direction: direction,
          description: desc,
          currency: currency,
        ),
      );
    }

    return result;
  }

  /// Unticks the rows of [rows] that look already imported from [sourceId],
  /// marks them [ParsedTransaction.likelyDuplicate], and returns how many.
  ///
  /// The save step's hash catches an exact re-import, but it includes the
  /// description, and on the AI tiers that is the model's wording: it changes
  /// between runs, and never matches the rules tier's bank text. Re-importing
  /// an overlapping statement through AI, or the same file through another
  /// tier, wrote every overlapping row a second time (audit A-1).
  ///
  /// So rows are matched on day, amount and direction, as a count: a file
  /// with three coffees on a day the source already has two of brings one. A
  /// stored row with the same description is matched first, so that when the
  /// counts leave one row new, it is the one with a description not seen
  /// before. And this only unticks — it never drops a row — because two
  /// different transactions can share a day, an amount and a direction; the
  /// preview says so and the user can tick a row back in.
  Future<int> markLikelyDuplicates(
    List<ParsedTransaction> rows,
    int sourceId,
  ) async {
    final stored =
        await (db.select(db.importedTransactions)
          ..where((t) => t.sourceId.equals(sourceId))).get();
    if (stored.isEmpty) return 0;

    String normal(String description) =>
        description.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    // The day, not the instant: an AI tier's dates and the rules tier's need
    // not carry the same time of day.
    String key(DateTime date, int cents, String direction) =>
        '${_dayKey(date)}|$cents|$direction';

    final unmatched = <String, List<String>>{};
    for (final r in stored) {
      (unmatched[key(r.date, r.amountCents, r.direction)] ??= []).add(
        normal(r.rawDescription),
      );
    }
    final byKey = <String, List<ParsedTransaction>>{};
    for (final tx in rows) {
      final k = key(
        tx.date,
        _toSmallestUnit(tx.amount, tx.currency),
        tx.direction,
      );
      if (unmatched.containsKey(k)) (byKey[k] ??= []).add(tx);
    }

    var marked = 0;
    void mark(ParsedTransaction tx) {
      tx
        ..likelyDuplicate = true
        ..include = false;
      marked++;
    }

    for (final MapEntry(key: k, value: candidates) in byKey.entries) {
      final pool = unmatched[k]!;
      final rest = <ParsedTransaction>[];
      // The same description first…
      for (final tx in candidates) {
        if (pool.remove(normal(tx.rawDescription))) {
          mark(tx);
        } else {
          rest.add(tx);
        }
      }
      // …then reworded ones, for as many stored rows as are left.
      rest.take(pool.length).forEach(mark);
    }
    return marked;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The source-scoped hash that stops a re-import writing a row twice.
  ///
  /// [occurrence] is how many identical rows (same date, unsigned amount and
  /// description) came before this one in the same file. Without it the
  /// second of two identical bus fares — or a refund, which has the same
  /// unsigned amount as its charge — was dropped as a duplicate. The first
  /// occurrence hashes exactly as before, so files imported earlier still
  /// dedupe.
  String computeHash(
    int sourceId,
    DateTime date,
    int amountCents,
    String rawDescription, {
    int occurrence = 0,
  }) {
    final input =
        '$sourceId|${date.toIso8601String()}|$amountCents|$rawDescription'
        '${occurrence == 0 ? '' : '#$occurrence'}';
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// The salt for an imported row's `Transactions.dedupHash`: the source,
  /// plus the row's [occurrence] among identical signed rows in its file
  /// (see [computeHash]).
  @visibleForTesting
  static String importDedupSalt(int sourceId, int occurrence) =>
      'source_$sourceId${occurrence == 0 ? '' : '#$occurrence'}';

  static bool _isBitcoinCurrency(String currency) =>
      currency == 'BTC' || currency == 'SATS';

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

  /// Reads a statement as text, tolerating the encodings banks actually use.
  ///
  /// `readAsString` uses the strict UTF-8 codec, so a single `£` (0xA3) in a
  /// legacy export throws and the whole file is reported as an unrecognised
  /// layout. Windows-1252 is the usual culprit, so fall back to Latin-1.
  Future<String> _readTextFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  List<List<String>> _parseCsvRows(String content) {
    // A leading BOM is invisible but sticks to the first header, so
    // 'date' != '\uFEFFdate' and column detection fails on a textbook CSV.
    var text = content.startsWith('\uFEFF') ? content.substring(1) : content;
    // Classic Mac exports end lines with a bare `\r`; normalising only `\r\n`
    // left such a file as one enormous row.
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = CsvToListConverter(
      eol: '\n',
      fieldDelimiter: _sniffDelimiter(text),
      shouldParseNumbers: false,
    ).convert(text);
    return rows.map((r) => r.map((e) => e.toString()).toList()).toList();
  }

  /// Picks the field delimiter from the start of the file.
  ///
  /// Most of continental Europe exports semicolon-separated CSV (precisely
  /// because the comma is the decimal point). Assuming ',' turns such a file
  /// into one unusable column.
  ///
  /// Judged on consistency over the first lines rather than on the first line
  /// alone, which in many exports is a title or account summary rather than
  /// the header: the delimiter is the one that splits the most lines into the
  /// same number of fields.
  static String _sniffDelimiter(String text) {
    final lines =
        text.split('\n').where((l) => l.trim().isNotEmpty).take(20).toList();
    var best = ',';
    var bestScore = -1;
    var bestFields = 0;
    for (final candidate in const [',', ';', '\t', '|']) {
      // How many lines share each field count, ignoring lines it never splits.
      final tally = <int, int>{};
      for (final line in lines) {
        final count = _countOutsideQuotes(line, candidate);
        if (count > 0) tally[count] = (tally[count] ?? 0) + 1;
      }
      if (tally.isEmpty) continue;
      final mode = tally.entries.reduce((a, b) => b.value > a.value ? b : a);
      if (mode.value > bestScore ||
          (mode.value == bestScore && mode.key > bestFields)) {
        best = candidate;
        bestScore = mode.value;
        bestFields = mode.key;
      }
    }
    return best;
  }

  static int _countOutsideQuotes(String line, String char) {
    var count = 0;
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes && c == char) {
        count++;
      }
    }
    return count;
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

  /// Decides whether a `03/04/2025`-style column is day-first.
  ///
  /// Resolved once per file, not per row. Deciding per row meant a UK
  /// statement came out with the month and day swapped for days 1–12 only:
  /// `03/04/2025` read as 3 March, `13/04/2025` as 13 April, from two April
  /// rows. One of them then lands in the wrong month's budget and dashboard.
  ///
  /// A vote across every decisive date, not the first one found: a merged
  /// UK export with one US-formatted row used to be read month-first
  /// throughout if that row happened to come first. Each row's own decisive
  /// component still overrides the file's answer in [_parseDate].
  ///
  /// Falls back to month-first (US) when a file is genuinely ambiguous — every
  /// date in it has both components ≤ 12, or the vote is tied — which is the
  /// format the manual mapper also defaults to.
  static bool _inferDayFirst(Iterable<String> samples) {
    var dayFirst = 0;
    var monthFirst = 0;
    for (final sample in samples) {
      final m = RegExp(
        r'^\s*"?(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})',
      ).firstMatch(sample.trim());
      if (m == null) continue;
      final first = int.parse(m.group(1)!);
      final second = int.parse(m.group(2)!);
      if (first > 12 && second <= 12) dayFirst++; // first can only be a day
      if (second > 12 && first <= 12) monthFirst++; // second can only be one
    }
    return dayFirst > monthFirst;
  }

  DateTime? _parseDate(String raw, {bool dayFirst = false}) {
    raw = raw.trim().replaceAll('"', '');
    if (raw.isEmpty) return null;

    // YYYY-MM-DD or YYYY-MM-DDTHH:mm
    final iso = RegExp(r'^(\d{4})[-/](\d{2})[-/](\d{2})').firstMatch(raw);
    if (iso != null) {
      return _calendarDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    // Two numbers then a year, separated by / - or . — the last covers
    // continental exports like 01.02.2025, which used to parse as nothing at
    // all. [dayFirst] settles the order; a component > 12 overrides it, since
    // it can only be a day whatever the file's convention is.
    final numeric = RegExp(
      r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})(?!\d)',
    ).firstMatch(raw);
    if (numeric != null) {
      final first = int.parse(numeric.group(1)!);
      final second = int.parse(numeric.group(2)!);
      final yearText = numeric.group(3)!;
      final yr =
          yearText.length == 2
              ? _expandYear(int.parse(yearText))
              : int.parse(yearText);
      final firstIsDay = first > 12 || (dayFirst && second <= 12);
      final dy = firstIsDay ? first : second;
      final mo = firstIsDay ? second : first;
      final date = _calendarDate(yr, mo, dy);
      if (date != null) return date;
    }
    // DD MMM YYYY  or  MMM DD YYYY
    final months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final dmy = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})').firstMatch(raw);
    if (dmy != null) {
      final mo = months[dmy.group(2)!.toLowerCase()];
      if (mo != null) {
        return _calendarDate(
          int.parse(dmy.group(3)!),
          mo,
          int.parse(dmy.group(1)!),
        );
      }
    }
    final mdy = RegExp(r'^([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})').firstMatch(raw);
    if (mdy != null) {
      final mo = months[mdy.group(1)!.toLowerCase()];
      if (mo != null) {
        return _calendarDate(
          int.parse(mdy.group(3)!),
          mo,
          int.parse(mdy.group(2)!),
        );
      }
    }
    return null;
  }

  /// The calendar date [year]-[month]-[day], or null if there is none.
  ///
  /// `DateTime(2025, 25, 12)` is not an error, it is December 2026 — and
  /// `DateTime.tryParse` normalises the same way — so a day/month mix-up came
  /// out as a date a year or two away rather than being rejected.
  static DateTime? _calendarDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    return date.month == month && date.day == day ? date : null;
  }

  /// [raw] read in the column mapper's chosen [format].
  ///
  /// Any of `/`, `-` and `.` separates the parts: the format names the order,
  /// and a DD/MM export written 25.12.2025 or 25-12-2025 used to fall through
  /// to the guessing parser. A date that does not exist in the chosen order is
  /// rejected, so a wrong choice shows as unparsed rows rather than as dates.
  DateTime? _parseDateWithFormat(String raw, String format) {
    raw = raw.trim().replaceAll('"', '');
    if (raw.isEmpty) return null;
    final ymd = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)');
    final xyY = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})(?!\d)');
    final xyy = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2})(?!\d)');
    int g(RegExpMatch m, int i) => int.parse(m.group(i)!);

    switch (format) {
      case 'YYYY-MM-DD':
        final m = ymd.firstMatch(raw);
        return m == null ? null : _calendarDate(g(m, 1), g(m, 2), g(m, 3));
      case 'MM/DD/YYYY' || 'MM-DD-YYYY':
        final m = xyY.firstMatch(raw);
        return m == null ? null : _calendarDate(g(m, 3), g(m, 1), g(m, 2));
      case 'DD/MM/YYYY':
        final m = xyY.firstMatch(raw);
        return m == null ? null : _calendarDate(g(m, 3), g(m, 2), g(m, 1));
      case 'MM/DD/YY':
        final m = xyy.firstMatch(raw);
        return m == null
            ? null
            : _calendarDate(_expandYear(g(m, 3)), g(m, 1), g(m, 2));
      case 'DD/MM/YY':
        final m = xyy.firstMatch(raw);
        return m == null
            ? null
            : _calendarDate(_expandYear(g(m, 3)), g(m, 2), g(m, 1));
    }
    return _parseDate(raw);
  }

  double? _parseAmount(String raw, {bool dotGroupsThousands = false}) {
    if (raw.trim().isEmpty) return null;
    var s = raw
        .trim()
        .replaceAll('"', '')
        .replaceAll(r'$', '')
        .replaceAll('£', '')
        .replaceAll('€', '')
        .replaceAll('₿', '');

    // UK statements put the side of the ledger in a DR/CR suffix instead of a
    // sign: '12.50 DR' is money out. Without this the row is dropped outright.
    var forceNegative = false;
    final drcr = RegExp(r'\s*(DR|CR)\.?$', caseSensitive: false).firstMatch(s);
    if (drcr != null) {
      forceNegative = drcr.group(1)!.toUpperCase() == 'DR';
      s = s.substring(0, drcr.start);
    }

    // An ISO code before or after the figure — `GBP 12.50`, `12,50 EUR` —
    // which used to make the whole amount unreadable.
    s = s.replaceFirst(RegExp(r'^[A-Za-z]{3}\s*|\s*[A-Za-z]{3}$'), '');

    // Parenthetical negatives: (4.50) → -4.50
    final paren = RegExp(r"^\(([0-9,.\s'’]+)\)$").firstMatch(s);
    if (paren != null) s = '-${paren.group(1)}';
    // Every kind of space a locale groups thousands with — including the
    // narrow no-break space (U+202F) French formatting uses, which `' '` and
    // U+00A0 did not cover — and the Swiss apostrophe.
    s = s.replaceAll(RegExp(r"[\s'’]"), '');
    s = _normalizeDecimalSeparator(s, dotGroupsThousands: dotGroupsThousands);
    // Trailing minus sign: 4.50- → -4.50
    if (s.endsWith('-')) s = '-${s.substring(0, s.length - 1)}';

    final value = double.tryParse(s);
    if (value == null) return null;
    return forceNegative ? -value.abs() : value;
  }

  /// Works out whether `,` is a thousands separator or the decimal point.
  ///
  /// Stripping every comma — what this used to do — turns the German `-12,50`
  /// into `-1250.00` and records a €1,250 expense, with nothing to tell the
  /// user it happened.
  ///
  /// Dots alone are the mirror problem, and harder: `2.500` is two thousand
  /// five hundred in a German export and 2.5 BTC-ish anywhere else. Two or
  /// more dot groups (`1.234.567`) can only be grouping, so that is always
  /// read as such. A single group of exactly three digits is decided by
  /// [dotGroupsThousands], which the caller infers once per file from the
  /// file's other amounts — see [_inferDotGrouping]. It used to be read as a
  /// decimal unconditionally, so `2.500` became 2.5, a 1000× understatement,
  /// and `1.234.567` dropped the row.
  static String _normalizeDecimalSeparator(
    String s, {
    bool dotGroupsThousands = false,
  }) {
    final lastComma = s.lastIndexOf(',');
    if (lastComma == -1) {
      if (_multiDotGrouped.hasMatch(s) ||
          (dotGroupsThousands && _dotGrouped.hasMatch(s))) {
        return s.replaceAll('.', '');
      }
      return s; // a decimal point: already Dart-parseable
    }
    final lastDot = s.lastIndexOf('.');

    // '1,234.56' — the dot is last, so commas group thousands.
    if (lastDot > lastComma) return s.replaceAll(',', '');

    // '1.234,56' — the comma is last, so dots group thousands.
    if (lastDot != -1) {
      return '${s.substring(0, lastComma).replaceAll('.', '')}'
          '.${s.substring(lastComma + 1)}';
    }

    // Commas only. Exactly 3 digits per group is a thousands separator
    // ('1,234'); anything else is a decimal comma ('12,5', '12,50').
    if (RegExp(r'^-?\d{1,3}(,\d{3})+$').hasMatch(s)) {
      return s.replaceAll(',', '');
    }
    return '${s.substring(0, lastComma).replaceAll(',', '')}'
        '.${s.substring(lastComma + 1)}';
  }

  /// `1.234.567` — only ever thousands grouping.
  static final _multiDotGrouped = RegExp(r'^[-+]?\d{1,3}(\.\d{3}){2,}-?$');

  /// `2.500` — grouping in some files, a three-place decimal in others.
  static final _dotGrouped = RegExp(r'^[-+]?\d{1,3}(\.\d{3})+-?$');

  /// Whether a file writes amounts the continental way: `.` grouping
  /// thousands and `,` as the decimal point.
  ///
  /// Decided by vote over the file's own amounts rather than per value,
  /// because a single value often cannot say: `2.500` is ambiguous on its own,
  /// but not in a file that also contains `12,50` or `1.234,56`. Values that
  /// prove the other convention (`12.50`, `1,234.56`) vote against. A file
  /// with no decisive value at all keeps the decimal-point reading, which is
  /// what keeps a BTC export's `0.125` from becoming 125.
  static bool _inferDotGrouping(Iterable<String> samples) {
    var continental = 0;
    var anglo = 0;
    for (final raw in samples) {
      final v = raw.replaceAll(RegExp(r'[^\d.,]'), '');
      if (v.isEmpty) continue;
      final lastComma = v.lastIndexOf(',');
      final lastDot = v.lastIndexOf('.');
      if (lastComma != -1 && lastDot != -1) {
        lastComma > lastDot ? continental++ : anglo++;
      } else if (lastComma != -1) {
        // `12,50` is a decimal comma; `1,234` is ambiguous grouping.
        if (RegExp(r',\d{1,2}$').hasMatch(v)) continental++;
      } else if (lastDot != -1) {
        if (RegExp(r'\.\d{1,2}$').hasMatch(v) ||
            RegExp(r'\.\d{4,}$').hasMatch(v)) {
          anglo++;
        } else if (RegExp(r'^\d{1,3}(\.\d{3}){2,}$').hasMatch(v)) {
          continental++;
        }
      }
    }
    return continental > anglo;
  }

  static const _categoryKeywords = <String, List<String>>{
    'Bitcoin': [
      'coinbase',
      'kraken',
      'binance',
      'river financial',
      'strike',
      'bitcoin',
      'btc',
      'swan',
      'cash app bitcoin',
      'fold',
    ],
    'Income': [
      'payroll',
      'salary',
      'direct dep',
      'zelle received',
      'venmo credit',
      'payment received',
      'refund',
      'cashback',
      'dividend',
      'interest paid',
      'credit interest',
      'interest earned',
      'deposit',
    ],
    'Food & Dining': [
      'restaurant',
      'cafe',
      'coffee',
      'pizza',
      'burger',
      'sushi',
      'mcdonald',
      'starbucks',
      'subway',
      'chipotle',
      'doordash',
      'ubereats',
      'grubhub',
      'deliveroo',
      'just eat',
      'tesco',
      'waitrose',
      'sainsbury',
      'whole foods',
      'trader joe',
      'grocery',
      'supermarket',
      'bakery',
      'deli',
      'dining',
      'diner',
      'panera',
      'dunkin',
      'chick-fil',
    ],
    'Transport': [
      // Multi-word entries exist to beat a shorter keyword in another
      // category: 'rent a car' outranks Housing's 'rent'.
      'rent a car', 'car rental', 'car hire',
      'uber', 'lyft', 'taxi', 'transit', 'metro', 'bus ', 'train',
      'amtrak', 'flight', 'airline', 'parking', 'toll', ' gas ',
      'petrol', 'shell', 'bp ', 'exxon', 'chevron', 'fuel', 'tfl ',
      'oyster', 'national rail', 'ryanair', 'easyjet',
    ],
    'Housing': [
      'rent',
      'mortgage',
      'hoa ',
      'electric',
      'water bill',
      'internet',
      'xfinity',
      'comcast',
      'at&t',
      'verizon',
      'spectrum',
      'landlord',
      'property',
    ],
    'Subscriptions': [
      'netflix',
      'spotify',
      'hulu',
      'disney+',
      'apple subscription',
      'google one',
      'youtube premium',
      'patreon',
      'twitch',
      'dropbox',
      'icloud',
      'microsoft 365',
      'adobe',
      'subscription',
      'annual fee',
      'monthly fee',
    ],
    'Shopping': [
      'amazon',
      'ebay',
      'etsy',
      'walmart',
      'target',
      'costco',
      'best buy',
      'ikea',
      'h&m',
      'zara',
      'nike',
      'adidas',
      'clothing',
      'apparel',
      'shoes',
      'shop',
    ],
    'Entertainment': [
      // Not a bare 'ticket': at six characters it outscored Transport's
      // 'train', 'bus' and 'metro' under the longest-match rule, so TRAIN
      // TICKET and BUS TICKET LONDON both came out as Entertainment. Length
      // is a proxy for specificity and this is where it fails.
      'cinema', 'movie', 'theater', 'concert', 'ticketmaster',
      'eventbrite', 'ticketmaster', 'amc ', 'regal ', 'bar ',
      'bowling', 'gym', 'fitness', 'sport', 'steam ',
    ],
  };

  /// Matchers for every keyword, built once.
  ///
  /// Bare `contains` matched inside words, which is how `PASSPORT OFFICE`
  /// became Entertainment (`sport`), `BARBERSHOP` became Shopping (`shop`) and
  /// `SHELL ENERGY ELECTRIC` became Transport. The boundaries are written as
  /// lookarounds rather than `\b` because several keywords end in punctuation
  /// — `disney+`, `at&t`, `chick-fil` — where `\b` asserts the opposite of
  /// what is wanted.
  static final Map<String, List<(RegExp, int)>> _keywordMatchers = {
    for (final entry in _categoryKeywords.entries)
      entry.key: [
        for (final keyword in entry.value)
          (
            RegExp('(?<![a-z0-9])${RegExp.escape(keyword.trim())}(?![a-z0-9])'),
            keyword.trim().length,
          ),
      ],
  };

  /// The best-matching category for [description], or null if nothing matched.
  ///
  /// Scores every keyword and takes the longest match rather than the first:
  /// `MONTHLY FEE REFUND` used to be Income, because Income's `refund` is
  /// checked before Subscriptions' `monthly fee`. The longer, more specific
  /// phrase should win, and with the categories in a map the old order was
  /// arbitrary anyway.
  String? matchCategory(String description) {
    final lower = description.toLowerCase();
    String? best;
    var bestLength = 0;
    for (final entry in _keywordMatchers.entries) {
      for (final (pattern, length) in entry.value) {
        if (length > bestLength && pattern.hasMatch(lower)) {
          best = entry.key;
          bestLength = length;
        }
      }
    }
    return best;
  }

  /// Builds a row with its category worked out once.
  ///
  /// Every parse tier used to repeat the five-field constructor and call the
  /// categoriser inline, so adding the fallback flag would have meant scoring
  /// each description twice.
  ParsedTransaction _categorised({
    required DateTime date,
    required double amount,
    required String direction,
    required String description,
    required String currency,
  }) {
    final result = _categorise(description);
    return ParsedTransaction(
      date: date,
      amount: amount,
      direction: direction,
      description: description,
      rawDescription: description,
      currency: currency,
      category: result.category,
      categoryIsFallback: result.isFallback,
    );
  }

  /// [matchCategory] with the fallback applied, and whether it was applied.
  ({String category, bool isFallback}) _categorise(String description) {
    final match = matchCategory(description);
    return match == null
        ? (category: 'Other', isFallback: true)
        : (category: match, isFallback: false);
  }
}
