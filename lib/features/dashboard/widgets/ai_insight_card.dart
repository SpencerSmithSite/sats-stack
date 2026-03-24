import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../main.dart' as app;

/// Shows the latest AI insight if available, otherwise a static Bitcoiner tip.
/// On mobile, AI features are disabled so this always shows a tip.
class AiInsightCard extends StatelessWidget {
  const AiInsightCard({
    super.key,
    this.cachedInsight,
    this.isGenerating = false,
    this.onRefresh,
  });

  final String? cachedInsight;
  final bool isGenerating;
  final VoidCallback? onRefresh;

  // Rotating tips shown when no AI insight is available
  static const _tips = [
    'Every dollar you save is a potential sat. The sats you don\'t buy today are the most expensive ones.',
    'Fiat leaks silently. Small recurring subscriptions add up to hundreds of sats a month.',
    'The inflation rate steals purchasing power every month. Stacking sats is the antidote.',
    'DCA beats timing. A fixed weekly buy eliminates the stress of market watching.',
    'Your biggest budget category is your biggest opportunity to stack more sats.',
  ];

  String get _tip {
    if (cachedInsight != null && cachedInsight!.isNotEmpty) return cachedInsight!;
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    return _tips[dayOfYear % _tips.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = app.aiEnabledNotifier.value;

    const accent = Color(0xFF6AB0E8);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = accent.withOpacity(isDark ? 0.12 : 0.08);
    final borderColor = accent.withOpacity(isDark ? 0.35 : 0.20);

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
                isDesktop ? Icons.auto_awesome : Icons.lightbulb_outline,
                size: 14,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                isDesktop ? 'AI Insight' : 'Tip',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (isDesktop && onRefresh != null)
                GestureDetector(
                  onTap: isGenerating ? null : onRefresh,
                  child: isGenerating
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
          isGenerating && (cachedInsight == null || cachedInsight!.isEmpty)
              ? Text(
                  'Generating insight…',
                  style: TextStyle(
                    color: accent.withOpacity(0.6),
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
          if (isDesktop) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => context.go('/ai'),
              child: Text(
                'Ask the AI analyst →',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: accent,
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
