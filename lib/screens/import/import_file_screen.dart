import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/services/import_service.dart';
import '../../main.dart' as app;
import 'import_column_mapper_screen.dart';
import 'import_preview_screen.dart';
import 'import_source_setup_screen.dart';

class ImportFileScreen extends StatefulWidget {
  const ImportFileScreen({super.key});

  @override
  State<ImportFileScreen> createState() => _ImportFileScreenState();
}

class _ImportFileScreenState extends State<ImportFileScreen> {
  bool _ollamaBannerDismissed = false;
  bool _isProcessing = false;
  String _processingMessage = '';

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
                      if (_ollamaBannerDismissed) {
                        return const SliverToBoxAdapter(child: SizedBox.shrink());
                      }
                      return SliverToBoxAdapter(
                        child: _OllamaBanner(
                          onDismiss: () =>
                              setState(() => _ollamaBannerDismissed = true),
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
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(_processingMessage),
                      ],
                    ),
                  ),
                ),
              ),
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
    final ollamaConnected = app.aiEnabledNotifier.value;

    // For PDFs without Ollama, prompt before proceeding
    if (isPdf && !ollamaConnected) {
      final proceed = await _showPdfNoAiDialog();
      if (!proceed) return;
    }

    await _processFile(
        filePath: file.path!, fileName: file.name, source: source);
  }

  Future<bool> _showPdfNoAiDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PDF without Ollama'),
        content: const Text(
          'PDF import works best with Ollama connected. Without it, '
          'only text-layer PDFs can be parsed and results may be incomplete.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              context.push('/settings');
            },
            child: const Text('Connect Ollama'),
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
      _processingMessage = 'Reading file…';
    });

    // Brief pause so the UI renders the overlay before we block
    await Future.delayed(const Duration(milliseconds: 80));

    setState(() {
      _processingMessage = fileName.toLowerCase().endsWith('.pdf')
          ? 'Extracting PDF text…'
          : 'Analyzing with AI…';
    });

    ImportResult result;
    try {
      result = await app.importService.importFile(
        filePath: filePath,
        fileName: fileName,
        sourceId: source.id,
      );
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading file: $e')),
        );
      }
      return;
    }

    setState(() => _isProcessing = false);
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
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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

class _OllamaBanner extends StatelessWidget {
  const _OllamaBanner({required this.onDismiss, required this.onConnect});

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
              'Connect Ollama for AI-powered imports — any bank format, any layout.',
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
    required this.onDelete,
  });

  final ImportSource source;
  final VoidCallback onImport;
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
