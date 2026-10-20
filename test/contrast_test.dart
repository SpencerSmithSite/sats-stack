/// Pins text contrast against WCAG AA (4.5:1) in both themes.
///
/// The light theme failed it widely — secondary text at 3.37:1 across 125
/// call sites, orange sats figures at 2.30:1, and banner copy set in its own
/// accent over a tint of that accent at 1.97–2.20:1. None of those were
/// hardcoded dark colours, which is what the earlier light-mode pass looked
/// for: they were colours tuned for dark and reused on light.
///
/// The first version of `legibleAccent` was itself wrong — it measured against
/// a tint over pure white, and the colours it produced failed at 4.19–4.44:1
/// on the off-white scaffold the banners actually sit on. These tests measure
/// against every real combination, so that cannot recur silently.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/shared/theme/app_colors.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const aa = 4.5;

/// Every background a banner actually sits on in light mode: 7–12% of the
/// accent, over a white card or the off-white scaffold.
List<Color> realTints(Color accent) => [
      for (final surface in const [
        AppColors.lightSurface,
        AppColors.lightBackground,
      ])
        for (final alpha in const [0.07, 0.08, 0.10, 0.12])
          Color.alphaBlend(accent.withValues(alpha: alpha), surface),
    ];

/// The accents the banners use.
const accents = {
  'info blue': Color(0xFF6AB0E8),
  'routed green': Color(0xFF6AC86A),
  'success': AppColors.success,
  'warning orange': AppColors.bitcoinOrange,
};

/// Runs [body] with a BuildContext under the real app theme.
Future<void> withTheme(
  WidgetTester tester,
  ThemeData theme,
  void Function(BuildContext context) body,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Builder(builder: (context) {
      body(context);
      return const SizedBox();
    }),
  ));
}

void main() {
  group('secondary text', () {
    testWidgets('clears AA on every light surface', (tester) async {
      await withTheme(tester, AppTheme.light(), (context) {
        final text = context.textSecondary;
        expect(text, AppColors.textSecondaryLight);
        for (final bg in const [
          AppColors.lightBackground,
          AppColors.lightSurface,
          Color(0xFFF0EDEA), // light surfaceContainerHighest
        ]) {
          expect(contrast(text, bg), greaterThanOrEqualTo(aa),
              reason: 'on $bg');
        }
      });
    });

    testWidgets('clears AA on every dark surface', (tester) async {
      await withTheme(tester, AppTheme.dark(), (context) {
        final text = context.textSecondary;
        expect(text, AppColors.textSecondaryDark);
        for (final bg in const [
          AppColors.darkBackground,
          AppColors.darkSurface,
        ]) {
          expect(contrast(text, bg), greaterThanOrEqualTo(aa),
              reason: 'on $bg');
        }
      });
    });

    test('no single grey could have served both themes', () {
      // Why this is two values and not one better constant: the old shared
      // value fails light while passing dark.
      expect(contrast(AppColors.textSecondaryDark, AppColors.lightBackground),
          lessThan(aa));
      expect(contrast(AppColors.textSecondaryDark, AppColors.darkBackground),
          greaterThanOrEqualTo(aa));
    });
  });

  group('orange as text', () {
    testWidgets('is legible on light surfaces', (tester) async {
      await withTheme(tester, AppTheme.light(), (context) {
        final text = context.bitcoinOrangeText;
        expect(contrast(text, AppColors.lightSurface), greaterThanOrEqualTo(aa));
        expect(
            contrast(text, AppColors.lightBackground), greaterThanOrEqualTo(aa));
      });
    });

    testWidgets('keeps the brand colour in dark mode', (tester) async {
      await withTheme(tester, AppTheme.dark(), (context) {
        expect(context.bitcoinOrangeText, AppColors.bitcoinOrange);
        expect(contrast(AppColors.bitcoinOrange, AppColors.darkSurface),
            greaterThanOrEqualTo(aa));
      });
    });

    test('the brand orange really does fail as light-mode text', () {
      expect(contrast(AppColors.bitcoinOrange, AppColors.lightSurface),
          lessThan(3.0)); // fails even the large-text threshold
    });
  });

  group('legibleAccent', () {
    testWidgets('clears AA against every real tint, in light mode',
        (tester) async {
      await withTheme(tester, AppTheme.light(), (context) {
        for (final entry in accents.entries) {
          final text = context.legibleAccent(entry.value);
          for (final tint in realTints(entry.value)) {
            expect(contrast(text, tint), greaterThanOrEqualTo(aa),
                reason: '${entry.key} on $tint');
          }
        }
      });
    });

    testWidgets('the raw accents fail, which is the bug it fixes',
        (tester) async {
      await withTheme(tester, AppTheme.light(), (context) {
        for (final entry in accents.entries) {
          final worst = realTints(entry.value)
              .map((t) => contrast(entry.value, t))
              .reduce((a, b) => a < b ? a : b);
          expect(worst, lessThan(aa), reason: entry.key);
        }
      });
    });

    testWidgets('leaves the accent alone in dark mode', (tester) async {
      await withTheme(tester, AppTheme.dark(), (context) {
        for (final accent in accents.values) {
          expect(context.legibleAccent(accent), accent);
        }
      });
    });

    testWidgets('darkens only as much as it needs to', (tester) async {
      // Not just black: the colour cue is the point of keeping the accent.
      await withTheme(tester, AppTheme.light(), (context) {
        for (final accent in accents.values) {
          final text = context.legibleAccent(accent);
          expect(text, isNot(const Color(0xFF000000)));
          expect(text.computeLuminance(), lessThan(accent.computeLuminance()));
        }
      });
    });
  });
}
