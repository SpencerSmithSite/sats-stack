import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart' as app;
import '../../shared/constants/app_constants.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/platform_utils.dart';
import '../../core/database/database.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  // Config chosen during onboarding
  String _currency = 'USD';
  ThemeMode _themeMode = ThemeMode.dark;
  late final TextEditingController _esploraCtrl;
  late final TextEditingController _ollamaCtrl;

  static const _pageCount = 8;

  void _next() {
    if (_page < _pageCount - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _previous() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    // Save currency
    app.currencyNotifier.value = _currency;
    await app.db.into(app.db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingCurrency,
            value: _currency,
          ),
        );
    app.btcPriceService.switchCurrency(_currency);

    // Save theme
    app.themeModeNotifier.value = _themeMode;
    final themeValue = switch (_themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await app.db.into(app.db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingThemeMode,
            value: themeValue,
          ),
        );

    // Save Bitcoin/Esplora server (empty = use default)
    await app.xpubService.saveSettings(url: _esploraCtrl.text.trim());
    await app.btcPriceService.loadSettings();

    // Save Ollama/AI server
    final ollamaUrl = _ollamaCtrl.text.trim();
    if (ollamaUrl.isNotEmpty) {
      await app.ollamaService.saveSettings(url: ollamaUrl);
      app.aiEnabledNotifier.value = PlatformUtils.isDesktop ||
          (ollamaUrl != AppConstants.defaultOllamaUrl);
    }

    // Mark onboarding complete
    await app.db.into(app.db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingOnboardingComplete,
            value: 'true',
          ),
        );

    if (mounted) context.go('/dashboard');
  }

  @override
  void initState() {
    super.initState();
    _esploraCtrl = TextEditingController();
    _ollamaCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _esploraCtrl.dispose();
    _ollamaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const _WelcomePage(),
                  const _FeaturesPage(),
                  const _TourPage(),
                  _CurrencyPage(
                    selected: _currency,
                    onChanged: (c) => setState(() => _currency = c),
                  ),
                  _ThemePage(
                    selected: _themeMode,
                    onChanged: (m) {
                      setState(() => _themeMode = m);
                      app.themeModeNotifier.value = m;
                    },
                  ),
                  _BitcoinServerPage(controller: _esploraCtrl),
                  _AiServerPage(controller: _ollamaCtrl),
                  const _ReadyPage(),
                ],
              ),
            ),
            _BottomBar(
              page: _page,
              pageCount: _pageCount,
              onNext: _next,
              onPrevious: _previous,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pages ─────────────────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.bitcoinOrange.withAlpha(26),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Text(
                '₿',
                style: TextStyle(
                  fontSize: 40,
                  color: AppColors.bitcoinOrange,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Sats Stack',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              color: AppColors.bitcoinOrange,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your finances.\nYour device.\nYour keys.',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'A Bitcoin-native budget tracker that lives entirely on your device. No cloud. No accounts. No compromises.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _FeaturesPage extends StatelessWidget {
  const _FeaturesPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            'Built for\nprivacy.',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 40),
          const _FeatureRow(
            icon: Icons.lock_outline,
            title: 'All data stays local',
            body:
                'Everything lives in an encrypted SQLite database on your device. Nothing leaves.',
          ),
          const SizedBox(height: 28),
          const _FeatureRow(
            icon: Icons.wifi_off_outlined,
            title: 'Fully offline',
            body:
                'Add transactions, track budgets, and review your stack — even on a plane.',
          ),
          const SizedBox(height: 28),
          const _FeatureRow(
            icon: Icons.currency_bitcoin,
            title: 'Think in sats',
            body:
                'Every expense is converted to its sats equivalent at the live BTC price.',
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _TourPage extends StatelessWidget {
  const _TourPage();

  static const _tabs = [
    (
      icon: Icons.dashboard_outlined,
      label: 'Dashboard',
      description:
          'Your monthly snapshot — net cashflow, spending breakdown, BTC equivalent, and a wallet breakdown.',
    ),
    (
      icon: Icons.receipt_long_outlined,
      label: 'Transactions',
      description:
          'Log expenses and income manually, import a bank CSV, or sync a Bitcoin xpub address.',
    ),
    (
      icon: Icons.pie_chart_outline,
      label: 'Budgets',
      description:
          'Set monthly spending caps per category. Get notified before you overspend.',
    ),
    (
      icon: Icons.trending_up_outlined,
      label: 'Stack',
      description:
          'Watch your cumulative sat balance grow. Set a savings goal and track your projected completion date.',
    ),
    (
      icon: Icons.auto_awesome_outlined,
      label: 'AI Analyst',
      description:
          'Ask questions about your finances in natural language. Runs locally via Ollama — no data ever leaves your device.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Everything\nin one place.',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final tab = _tabs[i];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(80),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.bitcoinOrange.withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(tab.icon,
                            color: AppColors.bitcoinOrange, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tab.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tab.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrencyPage extends StatelessWidget {
  const _CurrencyPage({
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  static const _currencies = [
    (code: 'USD', name: 'US Dollar', symbol: r'$'),
    (code: 'EUR', name: 'Euro', symbol: '€'),
    (code: 'GBP', name: 'British Pound', symbol: '£'),
    (code: 'CAD', name: 'Canadian Dollar', symbol: r'CA$'),
    (code: 'AUD', name: 'Australian Dollar', symbol: r'A$'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            'Pick your\ncurrency.',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'All fiat amounts will be shown in this currency. You can change it later in Settings.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          ...CurrencyUtils.supported.map((code) {
            final info = _currencies.firstWhere(
              (c) => c.code == code,
              orElse: () => (code: code, name: code, symbol: code),
            );
            final isSelected = selected == code;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => onChanged(code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.bitcoinOrange.withAlpha(26)
                        : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.bitcoinOrange
                          : theme.colorScheme.outlineVariant.withAlpha(80),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          info.symbol,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: isSelected
                                ? AppColors.bitcoinOrange
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              code,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(
                          Icons.check_circle,
                          color: AppColors.bitcoinOrange,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _ThemePage extends StatelessWidget {
  const _ThemePage({
    required this.selected,
    required this.onChanged,
  });

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            'Choose your\nlook.',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'You can always change this in Settings.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          _ThemeCard(
            mode: ThemeMode.dark,
            label: 'Dark',
            icon: Icons.dark_mode_outlined,
            preview: const _ThemePreview(isDark: true),
            selected: selected,
            onTap: onChanged,
          ),
          const SizedBox(height: 12),
          _ThemeCard(
            mode: ThemeMode.light,
            label: 'Light',
            icon: Icons.light_mode_outlined,
            preview: const _ThemePreview(isDark: false),
            selected: selected,
            onTap: onChanged,
          ),
          const SizedBox(height: 12),
          _ThemeCard(
            mode: ThemeMode.system,
            label: 'System',
            icon: Icons.brightness_auto_outlined,
            preview: const _ThemePreviewSystem(),
            selected: selected,
            onTap: onChanged,
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.mode,
    required this.label,
    required this.icon,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final String label;
  final IconData icon;
  final Widget preview;
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = selected == mode;
    return GestureDetector(
      onTap: () => onTap(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.bitcoinOrange.withAlpha(26)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.bitcoinOrange
                : theme.colorScheme.outlineVariant.withAlpha(80),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            preview,
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: isSelected
                        ? AppColors.bitcoinOrange
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.bitcoinOrange,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5);
    final card = isDark ? const Color(0xFF1C2533) : Colors.white;
    final bar = isDark ? const Color(0xFF1C2533) : const Color(0xFFE8E8E8);
    return _PreviewFrame(bg: bg, card: card, bar: bar);
  }
}

class _ThemePreviewSystem extends StatelessWidget {
  const _ThemePreviewSystem();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            bottomLeft: Radius.circular(6),
          ),
          child: SizedBox(
            width: 26,
            height: 44,
            child: _PreviewFrame(
              bg: const Color(0xFF0D1117),
              card: const Color(0xFF1C2533),
              bar: const Color(0xFF1C2533),
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(6),
            bottomRight: Radius.circular(6),
          ),
          child: SizedBox(
            width: 26,
            height: 44,
            child: _PreviewFrame(
              bg: const Color(0xFFF5F5F5),
              card: Colors.white,
              bar: const Color(0xFFE8E8E8),
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    required this.bg,
    required this.card,
    required this.bar,
    this.borderRadius,
  });
  final Color bg;
  final Color card;
  final Color bar;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius ?? BorderRadius.circular(6),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          const SizedBox(height: 5),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            height: 8,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            height: 5,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Spacer(),
          Container(
            height: 10,
            color: bar,
          ),
        ],
      ),
    );
  }
}

class _BitcoinServerPage extends StatelessWidget {
  const _BitcoinServerPage({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.bitcoinOrange.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.dns_outlined,
                    color: AppColors.bitcoinOrange, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Bitcoin server',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Sats Stack uses a public Mempool / Esplora server to sync Bitcoin wallet balances and look up historical prices.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'For maximum privacy, point this at your own self-hosted node.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: controller,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Mempool / Esplora URL',
              hintText: 'https://mempool.space/api',
              helperText: 'Leave blank to use mempool.space (default)',
            ),
          ),
          const SizedBox(height: 20),
          Builder(builder: (context) {
            const accent = Color(0xFF6AC86A);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withOpacity(isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: accent.withOpacity(isDark ? 0.35 : 0.20)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can change this later in Settings → Servers.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: accent,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _AiServerPage extends StatelessWidget {
  const _AiServerPage({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = PlatformUtils.isDesktop;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.bitcoinOrange.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome_outlined,
                    color: AppColors.bitcoinOrange, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'AI analyst',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            isDesktop
                ? 'Sats Stack can connect to a local Ollama instance to give you AI-powered insights about your finances — all on-device, no data sent to the cloud.'
                : 'Connect to an Ollama instance running on your home server or VPS to get AI-powered financial insights.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: controller,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Ollama server URL',
              hintText: isDesktop
                  ? 'http://localhost:11434'
                  : 'http://your-server:11434',
              helperText: isDesktop
                  ? 'Leave blank to use localhost:11434 (default)'
                  : 'Required to enable the AI tab on mobile',
            ),
          ),
          const SizedBox(height: 20),
          Builder(builder: (context) {
            const accent = Color(0xFF6AB0E8);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withOpacity(isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: accent.withOpacity(isDark ? 0.35 : 0.20)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isDesktop
                        ? 'Ollama must be running locally. You can install it at ollama.com.'
                        : 'The AI tab will appear once a valid server URL is saved. You can update this in Settings → Servers.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: accent,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          );
          }),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _ReadyPage extends StatelessWidget {
  const _ReadyPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.bitcoinOrange,
            size: 56,
          ),
          const SizedBox(height: 28),
          Text(
            "You're ready.",
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Start by adding a transaction manually, importing a bank CSV, or syncing a Bitcoin wallet via xpub.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          _TipRow(
            icon: Icons.receipt_long_outlined,
            text: 'Log income and expenses in the Transactions tab.',
          ),
          const SizedBox(height: 16),
          _TipRow(
            icon: Icons.pie_chart_outline,
            text: 'Set monthly budgets per category to control spending.',
          ),
          const SizedBox(height: 16),
          _TipRow(
            icon: Icons.trending_up_outlined,
            text: 'Watch your sat stack grow in the Stack tab.',
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.bitcoinOrange.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.bitcoinOrange, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
          ),
        ),
      ],
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.page,
    required this.pageCount,
    required this.onNext,
    required this.onPrevious,
  });

  final int page;
  final int pageCount;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  @override
  Widget build(BuildContext context) {
    final isFirst = page == 0;
    final isLast = page == pageCount - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 0, 36, 32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pageCount, (i) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == page ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == page
                      ? AppColors.bitcoinOrange
                      : AppColors.bitcoinOrange.withAlpha(64),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (!isFirst) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onPrevious,
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: isFirst ? 1 : 2,
                child: FilledButton(
                  onPressed: onNext,
                  child: Text(isLast ? 'Get Started' : 'Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
