import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/tappable.dart';

/// Shows the latest AI insight if available, otherwise a static Bitcoiner tip.
///
/// When the active backend would send the month's figures to a third party,
/// the insight is never generated on its own: the card offers a button that
/// names the recipient, and nothing is sent until it is pressed.
class AiInsightCard extends StatelessWidget {
  const AiInsightCard({
    super.key,
    this.aiEnabled = false,
    this.cachedInsight,
    this.isGenerating = false,
    this.onRefresh,
    this.offDeviceRecipient,
  });

  /// Whether an AI backend is configured at all. Passed in rather than read
  /// from the global notifier so the card rebuilds when it changes.
  final bool aiEnabled;

  final String? cachedInsight;
  final bool isGenerating;
  final VoidCallback? onRefresh;

  /// Named third party that would receive the figures, or null when generating
  /// sends nothing off the device.
  final String? offDeviceRecipient;

  // Rotating tips shown when no AI insight is available
  static const _tips = [
    'Every dollar you save is a potential sat. The sats you don\'t buy today are the most expensive ones.',
    'Fiat leaks silently. Small recurring subscriptions add up to hundreds of sats a month.',
    'The inflation rate steals purchasing power every month. Stacking sats is the antidote.',
    'DCA beats timing. A fixed weekly buy eliminates the stress of market watching.',
    'Your biggest budget category is your biggest opportunity to stack more sats.',
  ];

  String get _tip {
    if (cachedInsight != null && cachedInsight!.isNotEmpty) {
      return cachedInsight!;
    }
    final dayOfYear =
        DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    return _tips[dayOfYear % _tips.length];
  }

  bool get _hasInsight => cachedInsight != null && cachedInsight!.isNotEmpty;

  /// True when there is nothing to show yet and generating would mean sending
  /// the figures to a third party — so the user is asked rather than charged
  /// and uploaded behind their back.
  bool get _needsConsentToGenerate =>
      aiEnabled && offDeviceRecipient != null && !_hasInsight && !isGenerating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const accent = Color(0xFF6AB0E8);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = accent.withValues(alpha: isDark ? 0.12 : 0.08);
    final borderColor = accent.withValues(alpha: isDark ? 0.35 : 0.20);
    // The accent as text: 2.06:1 on this card's tint in light mode, which the
    // other banners' legibleAccent pass had missed here.
    final accentText = context.legibleAccent(accent);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                aiEnabled ? Icons.auto_awesome : Icons.lightbulb_outline,
                size: 14,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                aiEnabled ? 'AI Insight' : 'Tip',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: accentText,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (aiEnabled && onRefresh != null && !_needsConsentToGenerate)
                Tappable(
                  label:
                      isGenerating ? 'Generating insight' : 'Refresh insight',
                  onTap: isGenerating ? null : onRefresh,
                  child:
                      isGenerating
                          ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: accent,
                            ),
                          )
                          : Icon(Icons.refresh, size: 14, color: accent),
                ),
            ],
          ),
          const SizedBox(height: 10),
          isGenerating && !_hasInsight
              ? Text(
                'Generating insight…',
                // 1.53:1 as 60% of the accent; the secondary text colour reads
                // as "in progress" just as well.
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              )
              : Text(
                _tip,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.5,
                ),
              ),
          if (_needsConsentToGenerate) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.auto_awesome, size: 15),
                label: const Text('Generate an insight'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentText,
                  side: BorderSide(color: accent.withValues(alpha: 0.5)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sends this month\'s totals and category breakdown to '
              '$offDeviceRecipient.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          if (aiEnabled) ...[
            const SizedBox(height: 12),
            Tappable(
              onTap: () => context.go('/ai'),
              child: Text(
                'Ask the AI analyst →',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: accentText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
