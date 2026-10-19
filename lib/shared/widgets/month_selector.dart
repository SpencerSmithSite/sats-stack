/// The ‹ Month Year › control in the Dashboard, Budgets and Analytics app bars.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Steps between months.
///
/// There used to be three copies of this, and two of them drew the arrows as
/// a bare 20–22px icon in a `GestureDetector`: under half the 44px minimum
/// touch target, and announced by a screen reader as nothing at all. These
/// are `IconButton`s, which bring the 48px target, a tooltip and a label.
class MonthSelector extends StatelessWidget {
  const MonthSelector({
    super.key,
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;

  /// Null when [month] is the current month, which disables the button.
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    // Scales down rather than overflowing the app bar at large text sizes.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
            onPressed: onPrevious,
          ),
          // Announced when it changes, so stepping with a screen reader says
          // where it landed.
          Semantics(
            liveRegion: true,
            child: Text(
              DateFormat('MMMM yyyy').format(month),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
