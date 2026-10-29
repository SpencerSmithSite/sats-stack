import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// The one place that decides what colour a category is drawn in.
///
/// There were three copies of this map, and they disagreed: Shopping was
/// purple in Analytics, blue-grey on the dashboard chart and plain grey in the
/// CSV sheet, so the same spending looked like different spending depending on
/// which screen you were on. None of them consulted the colour the user had
/// actually chosen in Settings → Categories, which the `Categories` table has
/// stored all along, and a custom category fell through to grey — several of
/// them, all identical and indistinguishable in a pie chart.
abstract final class CategoryPalette {
  /// The nine seeded categories, in the colours the database seeds them with.
  static final _seeded = <String, Color>{
    for (final e in AppConstants.seededCategoryColours.entries)
      e.key: parseHex(e.value)!,
  };

  /// Distinct, legible in both themes, and deliberately not including the
  /// Bitcoin orange — that one means Bitcoin.
  static const _fallbacks = <Color>[
    Color(0xFF6E8ECC),
    Color(0xFF9B6FCF),
    Color(0xFFCC7A6E),
    Color(0xFF4FA3A0),
    Color(0xFFB08A3E),
    Color(0xFF7FA05A),
    Color(0xFFC06C9E),
    Color(0xFF5C7FB8),
  ];

  static const _unknown = Color(0xFF888780);

  /// The colour for [name].
  ///
  /// [userHex] is the category row's own `color` where the caller has it — the
  /// user picked it, so it wins. Failing that, a seeded category keeps its
  /// shipped colour and anything else gets a stable pick from [_fallbacks], so
  /// two custom categories are never the same colour by accident and a
  /// category does not change colour between screens or launches.
  static Color of(String? name, {String? userHex}) {
    final fromUser = parseHex(userHex);
    if (fromUser != null) return fromUser;
    if (name == null || name.isEmpty) return _unknown;
    final seeded = _seeded[name];
    if (seeded != null) return seeded;
    return _fallbacks[name.hashCode.abs() % _fallbacks.length];
  }

  /// Parses `#RRGGBB`, `RRGGBB` or `#AARRGGBB`. Null when [hex] is null, blank
  /// or not a colour — a bad value in the database should not crash a chart.
  static Color? parseHex(String? hex) {
    if (hex == null) return null;
    var text = hex.trim();
    if (text.startsWith('#')) text = text.substring(1);
    if (text.length == 6) text = 'FF$text';
    if (text.length != 8) return null;
    final value = int.tryParse(text, radix: 16);
    return value == null ? null : Color(value);
  }
}
