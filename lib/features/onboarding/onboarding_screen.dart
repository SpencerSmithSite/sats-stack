import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart' as app;
import '../../shared/constants/app_constants.dart';
import '../../shared/theme/app_colors.dart';
import '../../core/database/database.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pageCount = 3;

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

  Future<void> _finish() async {
    await app.db.into(app.db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingOnboardingComplete,
            value: 'true',
          ),
        );
    if (mounted) context.go('/dashboard');
  }

  @override
  void dispose() {
    _controller.dispose();
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
                children: const [
                  _WelcomePage(),
                  _FeaturesPage(),
                  _ReadyPage(),
                ],
              ),
            ),
            _BottomBar(
              page: _page,
              pageCount: _pageCount,
              onNext: _next,
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
            body: 'Everything lives in an encrypted SQLite database on your device. Nothing leaves.',
          ),
          const SizedBox(height: 28),
          const _FeatureRow(
            icon: Icons.wifi_off_outlined,
            title: 'Fully offline',
            body: 'Add transactions, track budgets, and review your stack — even on a plane.',
          ),
          const SizedBox(height: 28),
          const _FeatureRow(
            icon: Icons.currency_bitcoin,
            title: 'Think in sats',
            body: 'Every expense is converted to its sats equivalent at the live BTC price.',
          ),
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
  });

  final int page;
  final int pageCount;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
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
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onNext,
              child: Text(isLast ? 'Get Started' : 'Next'),
            ),
          ),
        ],
      ),
    );
  }
}
