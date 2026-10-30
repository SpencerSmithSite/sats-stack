/// The first three pages: the pitch, the feature list and the tour.
library;

import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';
import 'page_frame.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OnboardingPageFrame(
      children: [
        const Spacer(),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.bitcoinOrange.withAlpha(26),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              '₿',
              style: TextStyle(fontSize: 40, color: context.bitcoinOrangeText),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Sats Stack',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            color: context.bitcoinOrangeText,
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
            color: context.textSecondary,
            height: 1.6,
          ),
        ),
        const Spacer(flex: 2),
      ],
    );
  }
}

class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OnboardingPageFrame(
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
        // Both halves of what this used to say were false: the database is
        // plain SQLite, not encrypted by the app, and a wallet sync sends
        // its addresses to a block explorer. Say what is true instead — and
        // keep it true; it is the first privacy claim a user reads.
        const FeatureRow(
          icon: Icons.lock_outline,
          title: 'Your records stay here',
          body:
              'Kept in a database on this device — no account, no Sats Stack '
              'server. Wallet syncs and prices use a public server, or your '
              'own.',
        ),
        const SizedBox(height: 28),
        const FeatureRow(
          icon: Icons.wifi_off_outlined,
          title: 'Fully offline',
          body:
              'Add transactions, track budgets, and review your stack — even on a plane.',
        ),
        const SizedBox(height: 28),
        const FeatureRow(
          icon: Icons.currency_bitcoin,
          title: 'Think in sats',
          body:
              'Every expense is converted to its sats equivalent at the live BTC price.',
        ),
        const Spacer(flex: 2),
      ],
    );
  }
}

class TourPage extends StatelessWidget {
  const TourPage({super.key});

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
          'Log expenses and income by hand, import a statement — CSV, PDF or a '
          'photo — or follow a Bitcoin wallet from its extended public key.',
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
          'Ask questions about your finances in natural language, using a '
          'model on this device, your own server, or a hosted provider — you '
          'choose how private.',
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
              separatorBuilder: (_, _) => const SizedBox(height: 10),
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
                        child: Icon(
                          tab.icon,
                          color: AppColors.bitcoinOrange,
                          size: 20,
                        ),
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
                                color: context.textSecondary,
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

class FeatureRow extends StatelessWidget {
  const FeatureRow({
    super.key,
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
                  color: context.textSecondary,
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
