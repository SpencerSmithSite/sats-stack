/// The leaf widgets the Settings screen is built from.
///
/// Moved out of settings_screen.dart, which is the one screen the audit's
/// "split this up" note could not be applied to wholesale: its bulk is a
/// single state class holding every controller and every connection test, and
/// carving that into per-section files means passing all of it back in —
/// a design change, not a move. These are the parts that genuinely were just
/// sitting at the bottom of the file.
library;

import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';

class DataRoutingBanner extends StatelessWidget {
  const DataRoutingBanner({super.key, required this.usingDefault});

  final bool usingDefault;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (usingDefault) {
      return SettingsBanner(
        icon: Icons.public,
        iconColor: const Color(0xFF6AB0E8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Using public servers',
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.legibleAccent(const Color(0xFF6AB0E8)),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            RouteRow(
              label: 'Wallet sync',
              value: 'mempool.space',
            ),
            RouteRow(
              label: 'BTC price',
              value: 'mempool.space · CoinGecko (fallback)',
            ),
            RouteRow(
              label: 'Historical prices',
              value: 'mempool.space · CoinGecko (fallback)',
            ),
            const SizedBox(height: 4),
            Text(
              'The operators of these services can see which addresses and prices you request. '
              'Set a self-hosted server below to route all data through it instead.',
              // Theme text, not the accent: two paragraphs set in the accent over a
              // tint of it measured 1.97–2.20:1 in light mode.
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return SettingsBanner(
      icon: Icons.shield_outlined,
      iconColor: const Color(0xFF6AC86A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'All data routed through your server',
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.legibleAccent(const Color(0xFF6AC86A)),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          RouteRow(
            label: 'Wallet sync',
            value: 'Your server only',
          ),
          RouteRow(
            label: 'BTC price',
            value: 'Your server only',
          ),
          RouteRow(
            label: 'Historical prices',
            value: 'Your server only (mempool with price data required)',
          ),
          const SizedBox(height: 4),
          Text(
            'mempool.space and CoinGecko are never contacted. '
            'If your server does not support price history, '
            'imported transaction amounts will show as \$0.',
            // Theme text, not the accent: two paragraphs set in the accent over a
            // tint of it measured 1.97–2.20:1 in light mode.
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsBanner extends StatelessWidget {
  const SettingsBanner({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = iconColor.withValues(alpha: isDark ? 0.12 : 0.08);
    final border = iconColor.withValues(alpha: isDark ? 0.35 : 0.20);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class RouteRow extends StatelessWidget {
  const RouteRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              // Was the accent at 70% alpha — the worst ratio on the screen.
              style: TextStyle(
                fontSize: 11,
                color: context.textSecondary,
              ),
            ),
          ),
          Flexible(
            child: Text(
              '→  $value',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.textSecondary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          if (subtitle != null)
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          if (trailing != null) ...[
            const SizedBox(height: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}
