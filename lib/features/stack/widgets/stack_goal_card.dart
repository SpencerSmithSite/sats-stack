/// The stack-goal card — progress, projection, and the sheet that sets it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/currency_utils.dart';
import '../../../shared/utils/sat_converter.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/widgets/tappable.dart';

class StackGoalCard extends StatelessWidget {
  const StackGoalCard({
    super.key,
    required this.totalSats,
    required this.goalSats,
    required this.avgMonthlySats,
    required this.btcPrice,
    required this.onEdit,
    required this.currency,
  });

  /// See `StackHero.currency`.
  final String currency;
  final int totalSats;
  final int? goalSats;
  final int avgMonthlySats;
  final double? btcPrice;
  final VoidCallback onEdit;

  /// Returns the projected completion month, or null if not computable.
  DateTime? _projectedDate(int remaining) {
    if (avgMonthlySats <= 0 || remaining <= 0) return null;
    final monthsNeeded = (remaining / avgMonthlySats).ceil();
    final now = DateTime.now();
    return DateTime(now.year, now.month + monthsNeeded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fiatFmt = NumberFormat.currency(symbol: CurrencyUtils.symbolFor(currency), decimalDigits: 0);

    if (goalSats == null || goalSats! <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Tappable(
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withAlpha(60),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.flag_outlined, size: 18, color: context.textSecondary),
                const SizedBox(width: 10),
                Text(
                  'Set a stacking goal',
                  style: theme.textTheme.bodyMedium?.copyWith(color: context.textSecondary),
                ),
                const Spacer(),
                Icon(Icons.chevron_right, size: 18, color: context.textSecondary),
              ],
            ),
          ),
        ),
      );
    }

    final progress = (totalSats / goalSats!).clamp(0.0, 1.0);
    final remaining = goalSats! - totalSats;
    final progressColor = progress >= 1.0
        ? AppColors.success
        : progress > 0.7
            ? AppColors.bitcoinOrange
            : AppColors.success;
    final remainingFiat = btcPrice != null && btcPrice! > 0 && remaining > 0
        ? fiatFmt.format(remaining / 1e8 * btcPrice!)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Tappable(
        hint: 'Edits the goal',
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withAlpha(60),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: AppTextStyles.monoMedium.copyWith(
                      color: progressColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_formatSats(totalSats)} / ${_formatSats(goalSats!)} sats',
                    style: AppTextStyles.monoSmall.copyWith(color: context.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.edit_outlined, size: 14, color: context.textSecondary),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: progressColor.withAlpha(25),
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  minHeight: 8,
                ),
              ),
              if (remaining > 0 && remainingFiat != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${_formatSats(remaining)} sats to go ≈ $remainingFiat',
                  style: theme.textTheme.bodySmall?.copyWith(color: context.textSecondary),
                ),
                const SizedBox(height: 6),
                // ── Projection row ──────────────────────────────────────
                Row(
                  children: [
                    if (avgMonthlySats > 0) ...[
                      Icon(Icons.trending_up, size: 13, color: context.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '+${_formatSats(avgMonthlySats)} sats/mo avg',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (_projectedDate(remaining) case final date?) ...[
                      Icon(Icons.flag_outlined, size: 13, color: AppColors.bitcoinOrange),
                      const SizedBox(width: 4),
                      Text(
                        'Goal by ${DateFormat('MMM yyyy').format(date)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.bitcoinOrangeText,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ] else if (progress >= 1.0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      'Goal reached!',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatSats(int sats) => SatConverter.formatSats(sats);
}

class SetGoalSheet extends StatefulWidget {
  const SetGoalSheet({
    super.key,
    required this.current,
    required this.onSave,
  });
  final int? current;
  final ValueChanged<int> onSave;

  @override
  State<SetGoalSheet> createState() => _SetGoalSheetState();
}

class _SetGoalSheetState extends State<SetGoalSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.current != null ? widget.current.toString() : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
                  'Set Stack Goal',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: true,
                  style: AppTextStyles.monoLarge.copyWith(color: theme.colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Goal (sats)',
                    hintText: '1,000,000',
                    suffixText: 'sats',
                  ),
                ),
                const SizedBox(height: 8),
                // Quick-pick presets
                Wrap(
                  spacing: 8,
                  children: [
                    for (final preset in [100000, 1000000, 10000000, 21000000])
                      ActionChip(
                        label: Text(_abbrev(preset)),
                        onPressed: () => _ctrl.text = preset.toString(),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    final val = int.tryParse(_ctrl.text);
                    if (val != null && val > 0) {
                      widget.onSave(val);
                      Navigator.of(context).pop();
                    }
                  },
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                  child: const Text('Save Goal'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _abbrev(int sats) {
    if (sats >= 1000000) return '${sats ~/ 1000000}M';
    if (sats >= 1000) return '${sats ~/ 1000}k';
    return '$sats';
  }
}
