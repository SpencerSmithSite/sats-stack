import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../main.dart' as app;

// ── Message model ─────────────────────────────────────────────────────────────

enum _Role { user, assistant }

class _Msg {
  _Msg({required this.role, required this.content});
  final _Role role;
  final String content;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<_Msg> _messages = [];
  bool _isStreaming = false;
  String _streamingContent = '';
  String? _error;

  List<String> _models = [];
  bool _ollamaAvailable = false;
  bool _checking = true;
  String? _systemPrompt;

  static const _starters = [
    'Analyze my spending this month',
    'What is eating most of my income?',
    'How can I stack more sats?',
    'Is my budget healthy?',
    'Compare my spending to inflation',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await app.ollamaService.loadSettings();
    final available = await app.ollamaService.isAvailable();
    if (!mounted) return;

    if (!available) {
      setState(() { _ollamaAvailable = false; _checking = false; });
      return;
    }

    final models = await app.ollamaService.listModels();
    if (!mounted) return;

    // Auto-select first model if none saved
    if (app.ollamaService.selectedModel == null && models.isNotEmpty) {
      await app.ollamaService.saveSettings(model: models.first);
    }

    final prompt = await _buildSystemPrompt();

    setState(() {
      _ollamaAvailable = true;
      _checking = false;
      _models = models;
      _systemPrompt = prompt;
    });
  }

  Future<String> _buildSystemPrompt() async {
    final now = DateTime.now();
    final data = await app.dashboardService.getDashboard(now);
    final price = app.btcPriceService.priceNotifier.value ?? 0;
    return app.ollamaService.buildSystemPrompt(
      totalStackSats: data.totalStackSats,
      btcPrice: price,
      monthlyIncome: data.monthlyIncomeFiat,
      monthlySpending: data.monthlySpendingFiat,
      monthlySurplus: data.monthlySurplusFiat,
      spendingByCategory: data.spendingByCategory,
      stackGoalSats: data.stackGoalSats,
    );
  }

  List<Map<String, String>> _buildApiMessages(String userMessage) {
    final result = <Map<String, String>>[];
    if (_systemPrompt != null) {
      result.add({'role': 'system', 'content': _systemPrompt!});
    }
    for (final m in _messages) {
      result.add({
        'role': m.role == _Role.user ? 'user' : 'assistant',
        'content': m.content,
      });
    }
    result.add({'role': 'user', 'content': userMessage});
    return result;
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _inputCtrl.text).trim();
    if (text.isEmpty || _isStreaming) return;

    _inputCtrl.clear();
    final userMsg = _Msg(role: _Role.user, content: text);

    setState(() {
      _messages = [..._messages, userMsg];
      _isStreaming = true;
      _streamingContent = '';
      _error = null;
    });

    _scrollToBottom();

    final apiMessages = _buildApiMessages(text);
    final buffer = StringBuffer();

    try {
      await for (final token in app.ollamaService.chat(apiMessages)) {
        buffer.write(token);
        if (mounted) {
          setState(() => _streamingContent = buffer.toString());
          _scrollToBottom();
        }
      }
      final response = buffer.toString();
      // Save to DB
      await app.ollamaService.saveConversation(prompt: text, response: response);

      if (mounted) {
        setState(() {
          _messages = [..._messages, _Msg(role: _Role.assistant, content: response)];
          _isStreaming = false;
          _streamingContent = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isStreaming = false;
          _streamingContent = '';
          _error = 'Error: $e';
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OllamaSettingsSheet(
        currentUrl: app.ollamaService.baseUrl,
        currentModel: app.ollamaService.selectedModel,
        models: _models,
        onSave: (url, model) async {
          await app.ollamaService.saveSettings(url: url, model: model);
          if (mounted) setState(() {});
        },
        onRefresh: () async {
          final available = await app.ollamaService.isAvailable();
          if (!available) return;
          final models = await app.ollamaService.listModels();
          if (mounted) setState(() { _models = models; _ollamaAvailable = true; });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _checking
            ? const Text('AI Analyst')
            : _ollamaAvailable
                ? _ModelSelector(
                    models: _models,
                    selected: app.ollamaService.selectedModel,
                    onChanged: (m) async {
                      await app.ollamaService.saveSettings(model: m);
                      setState(() {});
                    },
                  )
                : const Text('AI Analyst'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
            tooltip: 'Ollama settings',
          ),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : !_ollamaAvailable
              ? _OfflineState(onRetry: _init)
              : Column(
                  children: [
                    Expanded(child: _ChatList(
                      messages: _messages,
                      isStreaming: _isStreaming,
                      streamingContent: _streamingContent,
                      scrollCtrl: _scrollCtrl,
                      starters: _starters,
                      onStarterTap: _send,
                    )),
                    if (_error != null)
                      _ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                    _InputBar(
                      controller: _inputCtrl,
                      isStreaming: _isStreaming,
                      onSend: _send,
                    ),
                  ],
                ),
    );
  }
}

// ── Chat list ─────────────────────────────────────────────────────────────────

class _ChatList extends StatelessWidget {
  const _ChatList({
    required this.messages,
    required this.isStreaming,
    required this.streamingContent,
    required this.scrollCtrl,
    required this.starters,
    required this.onStarterTap,
  });

  final List<_Msg> messages;
  final bool isStreaming;
  final String streamingContent;
  final ScrollController scrollCtrl;
  final List<String> starters;
  final ValueChanged<String> onStarterTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = messages.isEmpty && !isStreaming;

    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Starter prompts
        if (empty) ...[
          const SizedBox(height: 32),
          Center(
            child: Icon(Icons.auto_awesome_outlined,
                size: 40, color: const Color(0xFF6AB0E8)),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Bitcoin-native AI analyst',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Your financial data is injected as context.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in starters)
                ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  onPressed: () => onStarterTap(s),
                  backgroundColor: const Color(0xFF1A2A3A),
                  side: const BorderSide(color: Color(0xFF2A4A6A), width: 0.5),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],

        // Messages
        for (final msg in messages) _Bubble(msg: msg),

        // Streaming bubble
        if (isStreaming)
          _Bubble(
            msg: _Msg(role: _Role.assistant, content: streamingContent),
            streaming: true,
          ),

        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, this.streaming = false});

  final _Msg msg;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = msg.role == _Role.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF1A2A3A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2A4A6A), width: 0.5),
              ),
              child: const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF6AB0E8)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: msg.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser
                      ? AppColors.bitcoinOrange.withAlpha(25)
                      : const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: Border.all(
                    color: isUser
                        ? AppColors.bitcoinOrange.withAlpha(60)
                        : Colors.white.withAlpha(12),
                    width: 0.5,
                  ),
                ),
                child: streaming && msg.content.isEmpty
                    ? const _TypingIndicator()
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              msg.content,
                              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                            ),
                          ),
                          if (streaming) ...[
                            const SizedBox(width: 2),
                            const _Cursor(),
                          ],
                        ],
                      ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 36),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < 3; i++) ...[
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF6AB0E8),
                shape: BoxShape.circle,
              ),
            ),
            if (i < 2) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _Cursor extends StatefulWidget {
  const _Cursor();
  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 530))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 2, height: 14,
        color: _ctrl.value > 0.5 ? AppColors.bitcoinOrange : Colors.transparent,
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.isStreaming, required this.onSend});

  final TextEditingController controller;
  final bool isStreaming;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline.withAlpha(40))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 5,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: isStreaming ? 'Thinking…' : 'Ask anything…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: theme.colorScheme.outline.withAlpha(60)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
              onSubmitted: isStreaming ? null : (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(enabled: !isStreaming, onTap: onSend),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: enabled ? AppColors.bitcoinOrange : AppColors.textSecondary.withAlpha(60),
          shape: BoxShape.circle,
        ),
        child: enabled
            ? const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20)
            : const SizedBox(
                width: 20, height: 20,
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
      ),
    );
  }
}

// ── Offline state ─────────────────────────────────────────────────────────────

class _OfflineState extends StatelessWidget {
  const _OfflineState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.computer_outlined, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'Ollama not running',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Install Ollama and pull a model, then tap Retry.\n\nollama pull llama3.2',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppConstants.defaultOllamaUrl,
              style: AppTextStyles.monoSmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.danger.withAlpha(20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.danger),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, size: 16, color: AppColors.danger),
          ),
        ],
      ),
    );
  }
}

// ── Model selector (in app bar) ───────────────────────────────────────────────

class _ModelSelector extends StatelessWidget {
  const _ModelSelector({required this.models, required this.selected, required this.onChanged});
  final List<String> models;
  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) return const Text('AI Analyst');
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: models.contains(selected) ? selected : models.firstOrNull,
        isDense: true,
        icon: const Icon(Icons.expand_more, size: 18),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        dropdownColor: Theme.of(context).colorScheme.surface,
        items: [
          for (final m in models)
            DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 14))),
        ],
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }
}

// ── Ollama settings sheet ─────────────────────────────────────────────────────

class _OllamaSettingsSheet extends StatefulWidget {
  const _OllamaSettingsSheet({
    required this.currentUrl,
    required this.currentModel,
    required this.models,
    required this.onSave,
    required this.onRefresh,
  });

  final String currentUrl;
  final String? currentModel;
  final List<String> models;
  final Future<void> Function(String url, String? model) onSave;
  final Future<void> Function() onRefresh;

  @override
  State<_OllamaSettingsSheet> createState() => _OllamaSettingsSheetState();
}

class _OllamaSettingsSheetState extends State<_OllamaSettingsSheet> {
  late final TextEditingController _urlCtrl;
  String? _selectedModel;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.currentUrl);
    _selectedModel = widget.currentModel;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    setState(() { _testing = true; _testResult = null; });
    await widget.onSave(_urlCtrl.text.trim(), _selectedModel);
    await widget.onRefresh();
    final ok = await app.ollamaService.isAvailable();
    if (mounted) {
      setState(() {
        _testing = false;
        _testResult = ok ? 'Connected ✓' : 'Cannot reach Ollama at that URL';
      });
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  'Ollama Settings',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _urlCtrl,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Ollama URL',
                    hintText: 'http://localhost:11434',
                  ),
                  style: AppTextStyles.monoSmall.copyWith(color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 16),
                if (widget.models.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    value: widget.models.contains(_selectedModel) ? _selectedModel : widget.models.firstOrNull,
                    decoration: const InputDecoration(labelText: 'Model'),
                    items: [
                      for (final m in widget.models)
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: (v) => setState(() => _selectedModel = v),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_testResult != null) ...[
                  Text(
                    _testResult!,
                    style: TextStyle(
                      fontSize: 13,
                      color: _testResult!.contains('✓')
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _testing ? null : _testAndSave,
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                  child: _testing
                      ? const SizedBox(height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save & Test Connection'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
