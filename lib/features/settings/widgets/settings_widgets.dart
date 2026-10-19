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
  const DataRoutingBanner({
    super.key,required this.usingDefault});

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
                color: const Color(0xFF6AB0E8),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            RouteRow(
              label: 'Wallet sync',
              value: 'mempool.space',
              color: const Color(0xFF6AB0E8),
            ),
            RouteRow(
              label: 'BTC price',
              value: 'mempool.space · CoinGecko (fallback)',
              color: const Color(0xFF6AB0E8),
            ),
            RouteRow(
              label: 'Historical prices',
              value: 'mempool.space · CoinGecko (fallback)',
              color: const Color(0xFF6AB0E8),
            ),
            const SizedBox(height: 4),
            Text(
              'The operators of these services can see which addresses and prices you request. '
              'Set a self-hosted server below to route all data through it instead.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6AB0E8),
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
              color: const Color(0xFF6AC86A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          RouteRow(
            label: 'Wallet sync',
            value: 'Your server only',
            color: const Color(0xFF6AC86A),
          ),
          RouteRow(
            label: 'BTC price',
            value: 'Your server only',
            color: const Color(0xFF6AC86A),
          ),
          RouteRow(
            label: 'Historical prices',
            value: 'Your server only (mempool with price data required)',
            color: const Color(0xFF6AC86A),
          ),
          const SizedBox(height: 4),
          Text(
            'mempool.space and CoinGecko are never contacted. '
            'If your server does not support price history, '
            'imported transaction amounts will show as \$0.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6AC86A),
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
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

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
              style: TextStyle(
                fontSize: 11,
                color: color.withAlpha(180),
              ),
            ),
          ),
          Flexible(
            child: Text(
              '→  $value',
              style: TextStyle(
                fontSize: 11,
                color: color,
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
              color: AppColors.textSecondary,
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
                    color: AppColors.textSecondary,
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
