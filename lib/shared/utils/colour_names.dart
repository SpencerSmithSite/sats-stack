/// Spoken names for colour swatches.
library;

import 'package:flutter/painting.dart';

/// A plain name for [colour] — "Red", "Teal", "Grey" — for a screen reader to
/// say about a swatch that has no text. Coarse on purpose: it only has to
/// tell the options in one picker apart, not describe them exactly.
String colourName(Color colour) {
  final hsv = HSVColor.fromColor(colour);
  if (hsv.saturation < 0.15) {
    if (hsv.value > 0.85) return 'White';
    if (hsv.value < 0.2) return 'Black';
    return 'Grey';
  }
  final h = hsv.hue;
  if (h < 15 || h >= 345) return 'Red';
  if (h < 45) return 'Orange';
  if (h < 70) return 'Yellow';
  if (h < 150) return 'Green';
  if (h < 190) return 'Teal';
  if (h < 250) return 'Blue';
  if (h < 290) return 'Purple';
  return 'Pink';
}
