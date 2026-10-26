/// The last page, and the bar along the bottom of every page.
library;

import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';

class ReadyPage extends StatelessWidget {
  const ReadyPage({super.key});

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
              color: context.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          TipRow(
            icon: Icons.receipt_long_outlined,
            text: 'Log income and expenses in the Transactions tab.',
          ),
          const SizedBox(height: 16),
          TipRow(
            icon: Icons.pie_chart_outline,
            text: 'Set monthly budgets per category to control spending.',
          ),
          const SizedBox(height: 16),
          TipRow(
            icon: Icons.trending_up_outlined,
            text: 'Watch your sat stack grow in the Stack tab.',
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class TipRow extends StatelessWidget {
  const TipRow({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: context.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.textSecondary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
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
                  // The inactive dots were a quarter-strength orange, close to
                  // invisible on the light background.
                  color:
                      i == page
                          ? AppColors.bitcoinOrange
                          : context.textSecondary,
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
