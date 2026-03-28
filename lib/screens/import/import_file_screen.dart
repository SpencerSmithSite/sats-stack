import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/database/database.dart';
import '../../core/services/import_service.dart';
import '../../core/services/ollama_service.dart';
import '../../main.dart' as app;
import '../../shared/utils/platform_utils.dart';
import 'import_column_mapper_screen.dart';
import 'import_preview_screen.dart';
import 'import_source_setup_screen.dart';

class ImportFileScreen extends StatefulWidget {
  const ImportFileScreen({super.key});

  @override
  State<ImportFileScreen> createState() => _ImportFileScreenState();
}

class _ImportFileScreenState extends State<ImportFileScreen> {
  bool _aiBannerDismissed = false;

  // Processing state
  bool _isProcessing = false;
  String _currentStage = '';
  String _aiOutput = '';
  bool _showCancel = false;

  // Timers & subscriptions
  Timer? _cancelTimer;
  Timer? _timeoutTimer;
  StreamSubscription<String>? _tokenSub;
  final _tokenScrollController = ScrollController();

  // Stored for timeout "Map manually" fallback
  String? _processingFilePath;
  String? _processingFileName;
  ImportSource? _processingSource;

  // Image picking
  final _imagePicker = ImagePicker();

  @override
  void dispose() {
    _cancelTimer?.cancel();
    _timeoutTimer?.cancel();
    _tokenSub?.cancel();
    _tokenScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Source',
            onPressed: _addSource,
          ),
        ],
      ),
      body: Stack(
        children: [
          StreamBuilder<List<ImportSource>>(
            stream: app.importService.watchSources(),
            builder: (context, snap) {
              final sources = snap.data ?? [];
              return CustomScrollView(
                slivers: [
                  // AI connection banner
                  ValueListenableBuilder<bool>(
                    valueListenable: app.aiEnabledNotifier,
                    builder: (context, aiEnabled, _) {
                      if (aiEnabled) {
                        return const SliverToBoxAdapter(
                          child: _AiConnectedBanner(),
                        );
                      }
                      if (_aiBannerDismissed) {
                        return const SliverToBoxAdapter(child: SizedBox.shrink());
                      }
                      return SliverToBoxAdapter(
                        child: _AiBanner(
                          onDismiss: () =>
                              setState(() => _aiBannerDismissed = true),
                          onConnect: () => context.push('/settings'),
                        ),
                      );
                    },
                  ),

                  if (sources.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(onAdd: _addSource),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Import Sources',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverList.separated(
                        itemCount: sources.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, i) => _SourceCard(
                          source: sources[i],
                          onImport: () => _pickFile(sources[i]),
                          onImportImage: () => _pickImageForSource(sources[i]),
                          onDelete: () => _deleteSource(sources[i]),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),

          // Full-screen processing overlay
          if (_isProcessing) _ImportProgressOverlay(
            stage: _currentStage,
            aiOutput: _aiOutput,
            showCancel: _showCancel,
            scrollController: _tokenScrollController,
            onCancel: _cancelImport,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSource,
        icon: const Icon(Icons.add),
        label: const Text('Add Source'),
      ),
    );
  }

  Future<void> _addSource() async {
    await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => const ImportSourceSetupScreen(),
      ),
    );
    // Stream auto-updates the list
  }

  Future<void> _deleteSource(ImportSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Source?'),
        content: Text(
          'This will also delete all ${source.name} imported transactions. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await app.importService.deleteSource(source.id);
    }
  }

  Future<void> _pickFile(ImportSource source) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'pdf'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final isPdf = file.name.toLowerCase().endsWith('.pdf');
    final aiConnected = app.aiEnabledNotifier.value;

    // For PDFs without an AI provider, prompt before proceeding
    if (isPdf && !aiConnected) {
      final proceed = await _showPdfNoAiDialog();
      if (!proceed) return;
    }

    // Store for timeout fallback
    _processingFilePath = file.path;
    _processingFileName = file.name;
    _processingSource = source;

    await _processFile(
        filePath: file.path!, fileName: file.name, source: source);
  }

  Future<bool> _showPdfNoAiDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No AI provider connected'),
        content: const Text(
          'PDF import works best with an AI provider connected. Without it, '
          'only text-layer PDFs can be parsed and results may be incomplete.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              context.push('/settings');
            },
            child: const Text('Connect AI'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Try Anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _processFile({
    required String filePath,
    required String fileName,
    required ImportSource source,
  }) async {
    setState(() {
      _isProcessing = true;
      _currentStage = 'Reading your statement…';
      _aiOutput = '';
      _showCancel = false;
    });

    // Subscribe to live AI token stream
    _tokenSub = app.importService.importTokenStream.listen((token) {
      if (!mounted) return;
      setState(() => _aiOutput += token);
      // Auto-scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_tokenScrollController.hasClients) {
          _tokenScrollController.animateTo(
            _tokenScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
          );
        }
      });
    });

    // Show Cancel after 5 seconds
    _cancelTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isProcessing) setState(() => _showCancel = true);
    });

    // Timeout after 5 minutes
    _timeoutTimer = Timer(const Duration(minutes: 5), () {
      if (mounted && _isProcessing) _handleTimeout(source);
    });

    // Yield to the event loop so the overlay renders and the token stream
    // subscription is fully active before any import work begins.
    await Future.microtask(() {});

    ImportResult result;
    try {
      result = await app.importService.importFile(
        filePath: filePath,
        fileName: fileName,
        sourceId: source.id,
        onStageChange: (stage) {
          if (mounted) setState(() => _currentStage = stage);
        },
      );
    } on ImportCancelledException {
      _cleanupProcessing();
      return;
    } catch (e) {
      _cleanupProcessing();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading file: $e')),
        );
      }
      return;
    }

    _cleanupProcessing();
    if (!mounted) return;

    if (result.needsManualMapping) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImportColumnMapperScreen(
            result: result,
            sourceId: source.id,
            sourceName: source.name,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImportPreviewScreen(
            result: result,
            sourceId: source.id,
            sourceName: source.name,
          ),
        ),
      );
    }
  }

  void _cleanupProcessing() {
    _cancelTimer?.cancel();
    _timeoutTimer?.cancel();
    _tokenSub?.cancel();
    _cancelTimer = null;
    _timeoutTimer = null;
    _tokenSub = null;
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _showCancel = false;
        _aiOutput = '';
        _currentStage = '';
      });
    }
  }

  void _cancelImport() {
    app.importService.cancelImport();
    _cleanupProcessing();
  }

  void _handleTimeout(ImportSource source) {
    app.importService.cancelImport();
    _cleanupProcessing();
    if (!mounted) return;

    final isCsv = (_processingFileName ?? '').toLowerCase().endsWith('.csv');

    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Taking longer than expected'),
        content: const Text(
          'This is taking longer than expected.\n\n'
          'Try a smaller file, a faster model, or check that '
          'your AI provider is responding.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'dismiss'),
            child: const Text('Try Again'),
          ),
          if (isCsv)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'manual'),
              child: const Text('Map Columns Manually'),
            ),
        ],
      ),
    ).then((action) async {
      if (action == 'manual' &&
          _processingFilePath != null &&
          _processingFileName != null &&
          _processingSource != null) {
        final result = await app.importService.readCsvForManualMapping(
          _processingFilePath!,
          _processingFileName!,
        );
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImportColumnMapperScreen(
                result: result,
                sourceId: _processingSource!.id,
                sourceName: _processingSource!.name,
              ),
            ),
          );
        }
      }
    });
  }

  // ── Image import ──────────────────────────────────────────────────────────

  Future<void> _pickImageForSource(ImportSource importSource) async {
    // Require AI before picking
    if (!app.aiEnabledNotifier.value) {
      await _showImageNoAiDialog();
      return;
    }

    // Warn if model likely doesn't support vision
    final model = app.ollamaService.selectedModel;
    if (!OllamaService.looksLikeVisionModel(model)) {
      final action = await _showVisionWarningDialog(model ?? 'unknown');
      if (action == 'settings') {
        if (mounted) context.push('/settings');
        return;
      }
      if (action != 'continue') return;
    }

    // Pick image: bottom sheet on mobile, direct gallery on desktop
    if (PlatformUtils.isMobile) {
      final imageSource = await _showImageSourceSheet();
      if (imageSource == null) return;
      await _doPickImage(imageSource, importSource);
    } else {
      await _doPickImage(ImageSource.gallery, importSource);
    }
  }

  Future<ImageSource?> _showImageSourceSheet() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _doPickImage(ImageSource imageSource, ImportSource importSource) async {
    final XFile? image = await _imagePicker.pickImage(
      source: imageSource,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (image == null) return;
    await _processImage(
      filePath: image.path,
      fileName: image.name,
      source: importSource,
    );
  }

  Future<void> _processImage({
    required String filePath,
    required String fileName,
    required ImportSource source,
  }) async {
    setState(() {
      _isProcessing = true;
      _currentStage = 'Preparing image…';
      _aiOutput = '';
      _showCancel = false;
    });

    _tokenSub = app.importService.importTokenStream.listen((token) {
      if (!mounted) return;
      setState(() => _aiOutput += token);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_tokenScrollController.hasClients) {
          _tokenScrollController.animateTo(
            _tokenScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
          );
        }
      });
    });

    _cancelTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isProcessing) setState(() => _showCancel = true);
    });
    _timeoutTimer = Timer(const Duration(minutes: 5), () {
      if (mounted && _isProcessing) _handleImageTimeout();
    });

    await Future.microtask(() {});

    ImportResult result;
    try {
      result = await app.importService.importImage(
        imagePath: filePath,
        sourceId: source.id,
        onStageChange: (stage) {
          if (mounted) setState(() => _currentStage = stage);
        },
      );
    } on ImportCancelledException {
      _cleanupProcessing();
      return;
    } catch (e) {
      _cleanupProcessing();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing image: $e')),
        );
      }
      return;
    }

    _cleanupProcessing();
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImportPreviewScreen(
          result: result,
          sourceId: source.id,
          sourceName: source.name,
        ),
      ),
    );
  }

  Future<void> _showImageNoAiDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI required'),
        content: const Text(
          'Image import requires an AI provider with vision support. '
          'Connect Ollama, LM Studio, or Maple in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/settings');
            },
            child: const Text('Connect AI'),
          ),
        ],
      ),
    );
  }

  /// Returns 'settings', 'continue', or null (dismissed).
  Future<String?> _showVisionWarningDialog(String modelName) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vision not supported'),
        content: Text(
          'Your current model ($modelName) may not support image analysis. '
          'For best results, switch to a vision-capable model such as '
          'llama3.2-vision or llava in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'settings'),
            child: const Text('Go to Settings'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'continue'),
            child: const Text('Try Anyway'),
          ),
        ],
      ),
    );
  }

  void _handleImageTimeout() {
    app.importService.cancelImport();
    _cleanupProcessing();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Taking longer than expected'),
        content: const Text(
          'The AI is taking longer than expected to analyze the image.\n\n'
          'Try a smaller image, a faster vision model, or check that '
          'your AI provider is responding.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ImportProgressOverlay extends StatelessWidget {
  const _ImportProgressOverlay({
    required this.stage,
    required this.aiOutput,
    required this.showCancel,
    required this.scrollController,
    required this.onCancel,
  });

  final String stage;
  final String aiOutput;
  final bool showCancel;
  final ScrollController scrollController;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasOutput = aiOutput.isNotEmpty;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Importing…',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Indeterminate linear bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(minHeight: 4),
                    ),

                    const SizedBox(height: 14),

                    // Stage label
                    Text(
                      stage,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),

                    // Live AI token output
                    if (hasOutput) ...[
                      const SizedBox(height: 16),
                      Container(
                        height: 130,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: cs.outlineVariant.withOpacity(0.5)),
                        ),
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            // Show last 3 000 chars so the widget stays bounded
                            aiOutput.length > 3000
                                ? aiOutput.substring(
                                    aiOutput.length - 3000)
                                : aiOutput,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ),
                    ],

                    // Cancel button (delayed)
                    if (showCancel) ...[
                      const SizedBox(height: 20),
                      Center(
                        child: TextButton(
                          onPressed: onCancel,
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiConnectedBanner extends StatelessWidget {
  const _AiConnectedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1D9E75).withOpacity(0.12),
        border: Border.all(color: const Color(0xFF1D9E75).withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 16, color: Color(0xFF1D9E75)),
          const SizedBox(width: 8),
          Text(
            'AI-powered imports connected',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: const Color(0xFF1D9E75)),
          ),
        ],
      ),
    );
  }
}

class _AiBanner extends StatelessWidget {
  const _AiBanner({required this.onDismiss, required this.onConnect});

  final VoidCallback onDismiss;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7931A).withOpacity(0.12),
        border: Border.all(
            color: const Color(0xFFF7931A).withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome,
              size: 18, color: Color(0xFFF7931A)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Connect an AI provider for AI-powered imports — any bank format, any layout.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: onConnect,
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFF7931A)),
            child: const Text('Connect →'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file_outlined,
                size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No import sources yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Create a source for each account or exchange '
              'you want to import statements from.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Source'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.onImport,
    required this.onImportImage,
    required this.onDelete,
  });

  final ImportSource source;
  final VoidCallback onImport;
  final VoidCallback onImportImage;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon(source.type),
                  size: 20, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(source.name,
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    '${_typeLabel(source.type)} · ${source.currency}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showMenu(context),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.photo_camera_outlined),
              tooltip: 'Import from photo',
              onPressed: onImportImage,
              visualDensity: VisualDensity.compact,
            ),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Import'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final offset = button.localToGlobal(
        Offset(button.size.width, button.size.height / 2),
        ancestor: overlay);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          offset.dx, offset.dy, offset.dx + 1, offset.dy + 1),
      items: [
        const PopupMenuItem(value: 'delete', child: Text('Delete source')),
      ],
    ).then((v) {
      if (v == 'delete') onDelete();
    });
  }

  IconData _typeIcon(String type) => switch (type) {
        'bank' => Icons.account_balance,
        'credit_card' => Icons.credit_card,
        'loan' => Icons.paid,
        'bitcoin_exchange' => Icons.currency_bitcoin,
        'bitcoin_wallet' => Icons.account_balance_wallet,
        _ => Icons.receipt,
      };

  String _typeLabel(String type) => switch (type) {
        'bank' => 'Bank Account',
        'credit_card' => 'Credit Card',
        'loan' => 'Loan',
        'bitcoin_exchange' => 'Bitcoin Exchange',
        'bitcoin_wallet' => 'Bitcoin Wallet',
        _ => 'Other',
      };
}
