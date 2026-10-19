import 'package:flutter/material.dart';

abstract final class AppColors {
  // Brand
  static const bitcoinOrange = Color(0xFFF7931A);

  // Dark theme
  static const darkBackground = Color(0xFF0D0D0D);
  static const darkSurface = Color(0xFF1A1A1A);
  static const darkSurface2 = Color(0xFF242424);

  // Light theme
  static const lightBackground = Color(0xFFF9F7F4);
  static const lightSurface = Color(0xFFFFFFFF);

  // Semantic
  static const success = Color(0xFF1D9E75);
  static const danger = Color(0xFFE24B4A);

  // Text
  //
  // Secondary text is two values, not one, and nothing should read a single
  // constant for it. `#888780` was used for both themes: 5.39:1 on the dark
  // background, but 3.37:1 on the light one — below the 4.5:1 AA floor, at
  // 10–11px, across 125 call sites. No single grey can serve both: the
  // luminance a colour needs to clear 4.5:1 against near-black and against
  // near-white do not overlap. Read it through `context.textSecondary`, which
  // resolves from the active theme.
  static const textSecondaryDark = Color(0xFF888780);

  /// The lightest warm grey that clears 4.5:1 on the light background (5.39),
  /// on a white card (5.77) *and* on the tinted `surfaceContainerHighest`
  /// (≈4.95) — `#6F6E67` clears the first two and fails the third.
  static const textSecondaryLight = Color(0xFF67665F);

  /// Bitcoin orange darkened for use as *text* on a light surface.
  ///
  /// The brand orange is 2.30:1 on white — illegible as the 10–12px sats
  /// figures it was used for. This clears 5.67:1 on white and 5.30:1 on the
  /// light background. Fills, borders and icons keep the brand colour; only
  /// small text needs this. Read it through `context.bitcoinOrangeText`.
  static const bitcoinOrangeOnLight = Color(0xFF9A5600);

  // Borders
  static const borderDark = Color(0x80333333);
  static const borderLight = Color(0x80CCCCCC);
}

/// Theme-resolved colours for the two cases where one constant cannot serve
/// both themes.
extension AppColorsOf on BuildContext {
  /// Secondary text for the active theme. See [AppColors.textSecondaryLight].
  Color get textSecondary => Theme.of(this).colorScheme.onSurfaceVariant;

  /// Bitcoin orange that is legible as text in the active theme.
  Color get bitcoinOrangeText => Theme.of(this).brightness == Brightness.dark
      ? AppColors.bitcoinOrange
      : AppColors.bitcoinOrangeOnLight;

  /// [accent], darkened in light mode just enough to be legible as text on a
  /// banner tinted with that same accent. Unchanged in dark mode, where every
  /// accent here already passes.
  ///
  /// The info banners set their heading *and* their body copy in the accent,
  /// over an 8% tint of it — measured at 1.97:1 for the green and 2.20:1 for
  /// the blue, which is the least readable text in the app, in the banner that
  /// explains which third parties can see your Bitcoin addresses. Body copy
  /// moves to `onSurface`; headings keep their colour cue through this.
  ///
  /// Computed rather than hand-picked because each accent needs a different
  /// amount (the blue 34%, the green 37%), and computing it means any accent
  /// passed here meets the threshold rather than the four someone checked.
  Color legibleAccent(Color accent) {
    if (Theme.of(this).brightness == Brightness.dark) return accent;
    return _legibleOnTint.putIfAbsent(accent.toARGB32(), () {
      // Measured against the *worst* real background, not a convenient one:
      // the banners use 7–12% of the accent, over either a white card or the
      // off-white scaffold. Checking against 8% over white — the first
      // version of this — produced colours that then failed at 4.19–4.44:1
      // on the scaffold. The 12%-over-scaffold case is the darkest, so a
      // colour that clears it clears all eight combinations (≥4.65:1).
      final tint = Color.alphaBlend(
        accent.withValues(alpha: 0.12),
        AppColors.lightBackground,
      );
      // Step toward black until it clears 4.6:1 — 4.5 is the AA floor for
      // normal text, and the tenth is margin.
      for (var step = 0; step <= 100; step++) {
        final candidate =
            Color.lerp(accent, const Color(0xFF000000), step / 100)!;
        if (_contrast(candidate, tint) >= 4.6) return candidate;
      }
      return const Color(0xFF000000);
    });
  }
}

final Map<int, Color> _legibleOnTint = {};

/// WCAG 2 contrast ratio.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
