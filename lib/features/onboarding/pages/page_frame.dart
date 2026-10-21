/// The layout every text page of onboarding shares.
library;

import 'package:flutter/material.dart';

/// A column that is vertically spaced by its [Spacer]s when the page has
/// room, and scrolls when it does not — a small phone, a large text size, or
/// the keyboard up.
///
/// A [Spacer] needs a bounded height, which a scroll view does not give, so
/// the column is held at least as tall as the viewport by [ConstrainedBox] and
/// sized to its content by [IntrinsicHeight]. Without that, a Spacer inside a
/// scroll view throws in layout and the page renders blank; and a plain
/// [Column] with Spacers, which these pages used to be, overflows instead of
/// scrolling once the content is taller than the screen.
class OnboardingPageFrame extends StatelessWidget {
  const OnboardingPageFrame({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - padding.vertical).clamp(
                0,
                double.infinity,
              ),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }
}
