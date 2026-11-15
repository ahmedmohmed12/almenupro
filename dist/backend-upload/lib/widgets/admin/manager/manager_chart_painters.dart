import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';

class ManagerAreaChart extends StatefulWidget {
  const ManagerAreaChart({
    super.key,
    required this.values,
    this.labels = const [],
    this.height = 180,
  });

  final List<double> values;
  final List<String> labels;
  final double height;

  @override
  State<ManagerAreaChart> createState() => _ManagerAreaChartState();
}

class _ManagerAreaChartState extends State<ManagerAreaChart> {
  int? _hoverHour;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final maxValue = widget.values.fold<double>(0, math.max);
    final pointLabel = _hoverHour == null
        ? null
        : (widget.labels.length > _hoverHour!
              ? widget.labels[_hoverHour!]
              : '${s.tr('الساعة', 'Hour')} ${_hoverHour!.toString().padLeft(2, '0')}:00');
    final label = pointLabel == null
        ? s.tr('المبيعات حسب الفترة', 'Sales by period')
        : '$pointLabel  •  ${widget.values[_hoverHour!].toStringAsFixed(3)} ${s.currency}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapDown: (d) =>
                    _setHour(d.localPosition.dx, constraints.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _setHour(d.localPosition.dx, constraints.maxWidth),
                onTapUp: (_) => setState(() => _hoverHour = null),
                onHorizontalDragEnd: (_) => setState(() => _hoverHour = null),
                child: CustomPaint(
                  painter: _AreaPainter(
                    values: widget.values,
                    maxValue: maxValue,
                    highlight: _hoverHour,
                  ),
                  size: Size(constraints.maxWidth, widget.height),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _setHour(double dx, double width) {
    if (width <= 0 || widget.values.isEmpty) return;
    final hour = (dx / width * widget.values.length).floor().clamp(
      0,
      widget.values.length - 1,
    );
    setState(() => _hoverHour = hour);
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({
    required this.values,
    required this.maxValue,
    required this.highlight,
  });

  final List<double> values;
  final double maxValue;
  final int? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final n = values.length;
    final peak = maxValue <= 0 ? 1.0 : maxValue;
    Offset point(int i) {
      final x = n == 1 ? size.width / 2 : size.width * i / (n - 1);
      final y = size.height - (values[i] / peak) * (size.height - 8);
      return Offset(x, y);
    }

    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i < n; i++) {
      final p = point(i);
      if (i == 0) {
        path.lineTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path
      ..lineTo(size.width, size.height)
      ..close();

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF6B1124).withValues(alpha: 0.35),
          const Color(0xFF6B1124).withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, fill);

    final stroke = Paint()
      ..color = const Color(0xFF6B1124)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final line = Path();
    for (var i = 0; i < n; i++) {
      final p = point(i);
      if (i == 0) {
        line.moveTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(line, stroke);

    if (highlight != null) {
      final p = point(highlight!);
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()..color = const Color(0xFFD49A00).withValues(alpha: 0.7),
      );
      canvas.drawCircle(p, 5, Paint()..color = const Color(0xFFD49A00));
    }
  }

  @override
  bool shouldRepaint(covariant _AreaPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.highlight != highlight;
}

class ManagerDonutChart extends StatelessWidget {
  const ManagerDonutChart({super.key, required this.slices, this.size = 140});

  final List<({String label, double value, Color color})> slices;
  final double size;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (s, e) => s + e.value);
    return Row(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(slices: slices, total: total),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final slice in slices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: slice.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          slice.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        total <= 0
                            ? '0%'
                            : '${((slice.value / total) * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.total});

  final List<({String label, double value, Color color})> slices;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = size.shortestSide * 0.18;
    final arcRect = rect.deflate(inset);
    var start = -math.pi / 2;
    if (total <= 0) {
      canvas.drawArc(
        arcRect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = const Color(0xFFE2E8F0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.shortestSide * 0.16,
      );
      return;
    }
    for (final slice in slices) {
      final sweep = (slice.value / total) * math.pi * 2;
      canvas.drawArc(
        arcRect,
        start,
        sweep,
        false,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.butt
          ..strokeWidth = size.shortestSide * 0.16,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}
