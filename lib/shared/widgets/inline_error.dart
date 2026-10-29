import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// An error shown inside a bottom sheet, where the user is looking.
///
/// A snackbar raised from a sheet is shown by the screen's `Scaffold` — behind
/// the sheet — so a failed save or a rejected amount said nothing visible
/// until the sheet was closed. Renders nothing for a null [message].
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    final colour = context.legibleAccent(AppColors.danger);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 16, color: colour),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colour),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
