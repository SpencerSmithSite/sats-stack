/// Trailing figures that shrink instead of overflowing.
library;

import 'package:flutter/material.dart';

/// Caps a row's trailing column — usually its amounts — at [maxFraction] of
/// the screen width, scaling it down if it would not fit.
///
/// A non-flex trailing `Column` in a `Row` takes whatever width its text
/// wants, so at a large accessibility text size the row overflowed (the
/// yellow-and-black stripe) instead of giving way. Amounts are scaled rather
/// than ellipsised: a truncated figure is worse than a small one.
class ShrinkToFit extends StatelessWidget {
  const ShrinkToFit({
    super.key,
    required this.child,
    this.maxFraction = 0.45,
    this.alignment = Alignment.centerRight,
  });

  final Widget child;
  final double maxFraction;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * maxFraction,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: child,
      ),
    );
  }
}
