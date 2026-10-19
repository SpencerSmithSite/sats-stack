/// A small selected/unselected pill.
///
/// Shared by the chart's period row and the DCA simulator's amount row, which
/// is why it is not inside either of them.
library;

import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';

class PeriodChip extends StatelessWidget {
  const PeriodChip({
    super.key,required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.bitcoinOrange.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.bitcoinOrange : context.textSecondary.withAlpha(60),
            width: selected ? 1.0 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.bitcoinOrange : context.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
