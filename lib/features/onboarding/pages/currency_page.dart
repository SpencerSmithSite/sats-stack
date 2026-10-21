/// Currency and theme, the two choices that change how everything else in
/// onboarding is rendered.
library;

import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/currency_utils.dart';
import '../../../shared/widgets/tappable.dart';

class CurrencyPage extends StatelessWidget {
  const CurrencyPage({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  static const _currencies = [
    (code: 'USD', name: 'US Dollar', symbol: r'$'),
    (code: 'EUR', name: 'Euro', symbol: '€'),
    (code: 'GBP', name: 'British Pound', symbol: '£'),
    (code: 'CAD', name: 'Canadian Dollar', symbol: r'CA$'),
    (code: 'AUD', name: 'Australian Dollar', symbol: r'A$'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 48, 36, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick your\ncurrency.',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'All fiat amounts will be shown in this currency. You can change it later in Settings.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: CurrencyUtils.supported.length,
              itemBuilder: (context, index) {
                final code = CurrencyUtils.supported[index];
                final info = _currencies.firstWhere(
                  (c) => c.code == code,
                  orElse: () => (code: code, name: code, symbol: code),
                );
                final isSelected = selected == code;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Tappable(
                    selected: isSelected,
                    onTap: () => onChanged(code),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? AppColors.bitcoinOrange.withAlpha(26)
                                : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              isSelected
                                  ? AppColors.bitcoinOrange
                                  : theme.colorScheme.outlineVariant.withAlpha(
                                    80,
                                  ),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text(
                              info.symbol,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color:
                                    isSelected
                                        ? AppColors.bitcoinOrange
                                        : context.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  info.name,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  code,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: context.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.bitcoinOrange,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ThemePage extends StatelessWidget {
  const ThemePage({super.key, required this.selected, required this.onChanged});

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  static const _themeOptions = [
    (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined, false, false),
    (ThemeMode.light, 'Light', Icons.light_mode_outlined, true, false),
    (ThemeMode.system, 'System', Icons.brightness_auto_outlined, false, true),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 48, 36, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose your\nlook.',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'You can always change this in Settings.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: _themeOptions.length,
              itemBuilder: (context, index) {
                final (mode, label, icon, isLight, isSystem) =
                    _themeOptions[index];
                final Widget preview =
                    isSystem
                        ? const ThemePreviewSystem()
                        : ThemePreview(isDark: !isLight);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ThemeCard(
                    mode: mode,
                    label: label,
                    icon: icon,
                    preview: preview,
                    selected: selected,
                    onTap: onChanged,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ThemeCard extends StatelessWidget {
  const ThemeCard({
    super.key,
    required this.mode,
    required this.label,
    required this.icon,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final String label;
  final IconData icon;
  final Widget preview;
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = selected == mode;
    return Tappable(
      selected: isSelected,
      onTap: () => onTap(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? AppColors.bitcoinOrange.withAlpha(26)
                  : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected
                    ? AppColors.bitcoinOrange
                    : theme.colorScheme.outlineVariant.withAlpha(80),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            preview,
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color:
                        isSelected
                            ? AppColors.bitcoinOrange
                            : context.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.bitcoinOrange,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5);
    final card = isDark ? const Color(0xFF1C2533) : Colors.white;
    final bar = isDark ? const Color(0xFF1C2533) : const Color(0xFFE8E8E8);
    return PreviewFrame(bg: bg, card: card, bar: bar);
  }
}

class ThemePreviewSystem extends StatelessWidget {
  const ThemePreviewSystem({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            bottomLeft: Radius.circular(6),
          ),
          child: SizedBox(
            width: 26,
            height: 44,
            child: PreviewFrame(
              bg: const Color(0xFF0D1117),
              card: const Color(0xFF1C2533),
              bar: const Color(0xFF1C2533),
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(6),
            bottomRight: Radius.circular(6),
          ),
          child: SizedBox(
            width: 26,
            height: 44,
            child: PreviewFrame(
              bg: const Color(0xFFF5F5F5),
              card: Colors.white,
              bar: const Color(0xFFE8E8E8),
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
      ],
    );
  }
}

class PreviewFrame extends StatelessWidget {
  const PreviewFrame({
    super.key,
    required this.bg,
    required this.card,
    required this.bar,
    this.borderRadius,
  });
  final Color bg;
  final Color card;
  final Color bar;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius ?? BorderRadius.circular(6),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          const SizedBox(height: 5),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            height: 8,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            height: 5,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Spacer(),
          Container(height: 10, color: bar),
        ],
      ),
    );
  }
}
