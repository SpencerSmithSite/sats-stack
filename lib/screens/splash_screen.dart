import 'dart:math';

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  /// Called after the animation completes and the screen has faded out.
  final VoidCallback? onComplete;

  /// If provided, the splash will not transition until this future resolves
  /// (holds for at least 600 ms regardless).
  final Future<void>? initFuture;

  const SplashScreen({super.key, this.onComplete, this.initFuture});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _coin1Ctrl;
  late final AnimationController _coin2Ctrl;
  late final AnimationController _coin3Ctrl;
  late final AnimationController _shakeCtrl;
  late final AnimationController _fadeCtrl;

  late final Animation<double> _coin1Y;
  late final Animation<double> _coin2Y;
  late final Animation<double> _coin3Y;
  late final Animation<double> _shakeY;
  late final Animation<double> _fadeOut;

  int _visibleCoins = 0;

  @override
  void initState() {
    super.initState();

    _coin1Ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _coin2Ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _coin3Ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));

    // Each coin drops from 400px above its resting position with bounceOut easing.
    _coin1Y = Tween<double>(begin: -400.0, end: 0.0).animate(
        CurvedAnimation(parent: _coin1Ctrl, curve: Curves.bounceOut));
    _coin2Y = Tween<double>(begin: -400.0, end: 0.0).animate(
        CurvedAnimation(parent: _coin2Ctrl, curve: Curves.bounceOut));
    _coin3Y = Tween<double>(begin: -400.0, end: 0.0).animate(
        CurvedAnimation(parent: _coin3Ctrl, curve: Curves.bounceOut));

    // Subtle screen shake: 2 px down → -1 px up → settle.
    _shakeY = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 2.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 2.0, end: -1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: -1.0, end: 0.0), weight: 30),
    ]).animate(_shakeCtrl);

    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));

    _runSequence();
  }

  Future<void> _runSequence() async {
    // --- Bottom coin drops ---
    if (!mounted) return;
    setState(() => _visibleCoins = 1);
    await _coin1Ctrl.forward();
    _shakeCtrl.forward(from: 0);

    // --- Middle coin drops ---
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    setState(() => _visibleCoins = 2);
    await _coin2Ctrl.forward();
    _shakeCtrl.forward(from: 0);

    // --- Top coin drops ---
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    setState(() => _visibleCoins = 3);
    await _coin3Ctrl.forward();
    _shakeCtrl.forward(from: 0);

    // --- Hold, waiting for initFuture if provided ---
    if (widget.initFuture != null) {
      await Future.wait([
        widget.initFuture!,
        Future.delayed(const Duration(milliseconds: 600)),
      ]);
    } else {
      await Future.delayed(const Duration(milliseconds: 600));
    }

    // --- Fade out ---
    if (!mounted) return;
    await _fadeCtrl.forward();
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _coin1Ctrl.dispose();
    _coin2Ctrl.dispose();
    _coin3Ctrl.dispose();
    _shakeCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeOut,
      child: AnimatedBuilder(
        animation:
            Listenable.merge([_coin1Ctrl, _coin2Ctrl, _coin3Ctrl, _shakeCtrl]),
        builder: (context, _) {
          return ColoredBox(
            color: const Color(0xFF141414),
            child: Transform.translate(
              offset: Offset(0, _shakeY.value),
              child: CustomPaint(
                painter: _CoinStackPainter(
                  visibleCoins: _visibleCoins,
                  coin1OffsetY: _coin1Y.value,
                  coin2OffsetY: _coin2Y.value,
                  coin3OffsetY: _coin3Y.value,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom painter — draws 1–3 stacked coins matching the SVG icon geometry.
//
// SVG reference (1024×1024 viewBox):
//   cx=512, face ellipse rx=260 ry=72, rim height=58
//   coin center spacing=108 (bottom cy=620, mid cy=512, top cy=404)
//
// Flutter scale: coinRx = 100 → scale = 100/260
// ---------------------------------------------------------------------------
class _CoinStackPainter extends CustomPainter {
  final int visibleCoins;
  final double coin1OffsetY; // bottom coin animated Y offset (0 = resting)
  final double coin2OffsetY; // middle coin
  final double coin3OffsetY; // top coin

  _CoinStackPainter({
    required this.visibleCoins,
    required this.coin1OffsetY,
    required this.coin2OffsetY,
    required this.coin3OffsetY,
  });

  static const double _rx = 100.0;
  static const double _ry = 72.0 * _rx / 260.0; // ≈ 27.69
  static const double _rimH = 58.0 * _rx / 260.0; // ≈ 22.31
  static const double _spacing = 108.0 * _rx / 260.0; // ≈ 41.54

  // Contact-shadow ellipse (SVG: rx=230, ry=46, blur stdDeviation=14)
  static const double _shadowRx = 230.0 * _rx / 260.0; // ≈ 88.46
  static const double _shadowRy = 46.0 * _rx / 260.0; // ≈ 17.69
  static const double _shadowBlur = 14.0 * _rx / 260.0; // ≈ 5.38
  // Shadow sits 4 SVG-px above the coin center (scaled)
  static const double _shadowDy = 4.0 * _rx / 260.0; // ≈ 1.54

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    // Final resting Y for each coin center (relative to canvas center)
    final double yBot = cy + _spacing;
    final double yMid = cy;
    final double yTop = cy - _spacing;

    // Draw bottom-to-top so upper coins appear in front.
    if (visibleCoins >= 1) {
      _drawCoin(canvas, cx, yBot + coin1OffsetY, _CoinTier.bottom);
    }
    if (visibleCoins >= 2) {
      // Contact shadow sits on the bottom coin's face (coin1 is already landed).
      _drawShadow(canvas, cx, yBot - _shadowDy);
      _drawCoin(canvas, cx, yMid + coin2OffsetY, _CoinTier.middle);
    }
    if (visibleCoins >= 3) {
      // Contact shadow sits on the middle coin's face (coin2 is already landed).
      _drawShadow(canvas, cx, yMid - _shadowDy);
      _drawCoin(canvas, cx, yTop + coin3OffsetY, _CoinTier.top);
    }
  }

  void _drawShadow(Canvas canvas, double cx, double shadowCy) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, shadowCy),
        width: _shadowRx * 2,
        height: _shadowRy * 2,
      ),
      Paint()
        ..color = const Color(0x73000000) // black ~45% opacity
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, _shadowBlur),
    );
  }

  void _drawCoin(Canvas canvas, double cx, double coinCy, _CoinTier tier) {
    final faceRect = Rect.fromCenter(
      center: Offset(cx, coinCy),
      width: _rx * 2,
      height: _ry * 2,
    );
    // Lower ellipse rect used for the bottom curve of the rim.
    final lowerRect = Rect.fromCenter(
      center: Offset(cx, coinCy + _rimH),
      width: _rx * 2,
      height: _ry * 2,
    );

    // Rim path:
    //   1. Start at left edge of face equator.
    //   2. Arc along the bottom half of the face ellipse (left → right via bottom).
    //   3. Vertical line down rimH to right edge of lower ellipse.
    //   4. Arc along the bottom half of the lower ellipse (right → left via bottom).
    //   5. Close (implicit left vertical line back to start).
    final rimPath = Path()
      ..moveTo(cx - _rx, coinCy)
      ..arcTo(faceRect, pi, pi, false) // clockwise: 9-o'clock → 3-o'clock via 6-o'clock
      ..lineTo(cx + _rx, coinCy + _rimH)
      ..arcTo(lowerRect, 0, pi, false) // clockwise: 3-o'clock → 9-o'clock via 6-o'clock
      ..close();

    final List<Color> rimColors;
    final List<Color> faceColors;

    switch (tier) {
      case _CoinTier.bottom:
        // face-bot / rim-bot gradients from SVG
        rimColors = [const Color(0xFF7A4800), const Color(0xFF321800)];
        faceColors = [
          const Color(0xFFCC7818),
          const Color(0xFFA86008),
          const Color(0xFF6A3400),
        ];
      case _CoinTier.middle:
        // face-mid / rim-mid gradients from SVG
        rimColors = [const Color(0xFFA05808), const Color(0xFF4E2800)];
        faceColors = [
          const Color(0xFFF09020),
          const Color(0xFFD07810),
          const Color(0xFF8C4800),
        ];
      case _CoinTier.top:
        // face-top / rim-top gradients from SVG
        rimColors = [const Color(0xFFD07810), const Color(0xFF7A4200)];
        faceColors = [
          const Color(0xFFFFBE50),
          const Color(0xFFF7931A),
          const Color(0xFFB86000),
        ];
    }

    // Gradient rect spans the full coin width so left/right stops align correctly.
    final gradientRect = Rect.fromLTWH(cx - _rx, coinCy - _ry, _rx * 2, _ry * 2 + _rimH);

    canvas.drawPath(
      rimPath,
      Paint()
        ..shader = LinearGradient(colors: rimColors).createShader(gradientRect),
    );

    canvas.drawOval(
      faceRect,
      Paint()
        ..shader = LinearGradient(
          colors: faceColors,
          stops: const [0.0, 0.55, 1.0],
        ).createShader(faceRect),
    );
  }

  @override
  bool shouldRepaint(_CoinStackPainter old) =>
      visibleCoins != old.visibleCoins ||
      coin1OffsetY != old.coin1OffsetY ||
      coin2OffsetY != old.coin2OffsetY ||
      coin3OffsetY != old.coin3OffsetY;
}

enum _CoinTier { bottom, middle, top }
