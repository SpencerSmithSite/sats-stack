import 'package:flutter/material.dart';

abstract final class AppTextStyles {
  // Monospace — for sat amounts, addresses, hashes
  static const monoLarge = TextStyle(
    fontFamily: 'RobotoMono',
    fontSize: 32,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.5,
  );

  static const monoMedium = TextStyle(
    fontFamily: 'RobotoMono',
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  static const monoSmall = TextStyle(
    fontFamily: 'RobotoMono',
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  // Hero number — dashboard total sats display
  static const heroSats = TextStyle(
    fontFamily: 'RobotoMono',
    fontSize: 48,
    fontWeight: FontWeight.w300,
    letterSpacing: -1.0,
  );
}
