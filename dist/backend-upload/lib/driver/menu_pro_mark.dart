import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'driver_brand.dart';

class DriverBrandedSplash extends StatefulWidget {
  const DriverBrandedSplash({
    super.key,
    required this.loading,
    this.onDrawComplete,
  });

  final bool loading;
  final VoidCallback? onDrawComplete;

  @override
  State<DriverBrandedSplash> createState() => _DriverBrandedSplashState();
}

class _DriverBrandedSplashState extends State<DriverBrandedSplash>
    with TickerProviderStateMixin {
  late final AnimationController _draw;
  late final AnimationController _glow;
  var _notified = false;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _draw.addStatusListener((status) {
      if (status != AnimationStatus.completed || _notified) return;
      _notified = true;
      _glow.repeat(reverse: true);
      widget.onDrawComplete?.call();
    });
    _draw.forward();
  }

  @override
  void dispose() {
    _draw.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final markSize = (width * 0.78).clamp(240.0, 360.0);

    return Scaffold(
      backgroundColor: DriverBrand.canvas,
      body: AnimatedBuilder(
        animation: Listenable.merge([_draw, _glow]),
        builder: (context, _) {
          final glow = 0.18 + (_glow.isAnimating ? _glow.value * 0.14 : 0);
          final wordOpacity = const Interval(
            0.62,
            0.92,
            curve: Curves.easeOut,
          ).transform(_draw.value);
          final scale =
              0.92 +
              (const Interval(
                    0.0,
                    0.35,
                    curve: Curves.easeOutBack,
                  ).transform(_draw.value) *
                  0.08);

          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.12),
                    radius: 0.95,
                    colors: [
                      Color.lerp(DriverBrand.canvas, DriverBrand.gold, glow)!,
                      DriverBrand.canvas,
                      const Color(0xFFFFEDE0),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              Center(
                child: Transform.scale(
                  scale: scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: markSize,
                        height: markSize * 0.72,
                        child: CustomPaint(
                          painter: MenuProMarkPainter(progress: _draw.value),
                        ),
                      ),
                      Opacity(
                        opacity: wordOpacity,
                        child: const _SplashWordmark(),
                      ),
                      if (widget.loading) ...[
                        const SizedBox(height: 28),
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: DriverBrand.gold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SplashWordmark extends StatelessWidget {
  const _SplashWordmark();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Almenu',
                  style: TextStyle(
                    color: DriverBrand.gold,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    height: 1,
                  ),
                ),
                TextSpan(
                  text: 'pro',
                  style: TextStyle(
                    color: DriverBrand.maroon,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.tr('سائق المنيو برو', 'AlMenuPro Driver'),
          style: const TextStyle(
            color: DriverBrand.maroon,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class MenuProMarkPainter extends CustomPainter {
  const MenuProMarkPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final arcT = const Interval(
      0.0,
      0.58,
      curve: Curves.easeInOutCubic,
    ).transform(progress);
    final checkT = const Interval(
      0.42,
      0.86,
      curve: Curves.easeOutCubic,
    ).transform(progress);
    final center = Offset(size.width / 2, size.height * 0.52);
    final radius = size.width * 0.28;

    final arcPath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi * 0.78,
        math.pi * 1.44,
      );
    final checkPath = Path()
      ..moveTo(center.dx - radius * 0.38, center.dy + radius * 0.12)
      ..lineTo(center.dx - radius * 0.08, center.dy + radius * 0.52)
      ..lineTo(center.dx + radius * 0.5, center.dy - radius * 0.18);

    final arcPaint = Paint()
      ..color = DriverBrand.maroon
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.145
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final checkPaint = Paint()
      ..color = DriverBrand.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    _strokePartial(canvas, arcPath, arcPaint, arcT);
    _strokePartial(canvas, checkPath, checkPaint, checkT);
  }

  void _strokePartial(Canvas canvas, Path path, Paint paint, double t) {
    if (t <= 0) return;
    if (t >= 1) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * t), paint);
    }
  }

  @override
  bool shouldRepaint(covariant MenuProMarkPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
