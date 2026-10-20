/// Where wallet history is read from.
library;

import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';

class BitcoinServerPage extends StatelessWidget {
  const BitcoinServerPage({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable, because this page has a text field in it. The keyboard takes
    // roughly 300 px, `resizeToAvoidBottomInset` shrinks the body by that much,
    // and the content is a fixed ~370 px of Column whose only slack is two
    // Spacers that clamp at zero — so on a small phone it overflowed and the
    // field could end up underneath the keyboard. The AI provider page was
    // already built this way.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      child: ConstrainedBox(
        // Keeps the Spacers meaningful when there is room, so the page looks
        // the same as it always did on a normal screen.
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom -
              200,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.bitcoinOrange.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.dns_outlined,
                      color: AppColors.bitcoinOrange, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Bitcoin server',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Sats Stack uses a public Mempool / Esplora server to sync Bitcoin wallet balances and look up historical prices.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'For maximum privacy, point this at your own self-hosted node.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: controller,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Mempool / Esplora URL',
                hintText: 'https://mempool.space/api',
                helperText: 'Leave blank to use mempool.space (default)',
              ),
            ),
            const SizedBox(height: 20),
            Builder(builder: (context) {
              const accent = Color(0xFF6AC86A);
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: accent.withValues(alpha: isDark ? 0.35 : 0.20)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can change this later in Settings → Servers.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.legibleAccent(accent),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
