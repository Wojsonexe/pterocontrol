import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A minimal inline trend line — no axes, no labels, no grid — for
/// showing "this is moving, and roughly how" next to a current value
/// (CPU%/RAM/network on the Dashboard's resource-overview card). Draws
/// only from real samples the caller already has (see
/// `ServerMetricsHistory`); never interpolates or invents points beyond
/// what [values] contains.
///
/// Renders nothing but a flat baseline for 0-1 points (nothing to trend
/// yet) rather than an empty box or a crash — a server whose first poll
/// just landed still gets a stable-looking sparkline slot instead of
/// layout jumping in once a second sample arrives.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 28,
    this.strokeWidth = 1.6,
  });

  final List<double> values;
  final Color color;
  final double height;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(painter: _SparklinePainter(values: values, color: color, strokeWidth: strokeWidth)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color, required this.strokeWidth});

  final List<double> values;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final baselineY = size.height - strokeWidth;

    if (values.length < 2) {
      final dotCenter = Offset(size.width - strokeWidth, baselineY);
      canvas.drawCircle(dotCenter, strokeWidth * 1.4, Paint()..color = color.withValues(alpha: 0.5));
      return;
    }

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = (maxValue - minValue).abs() < 1e-9 ? 1.0 : (maxValue - minValue);

    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * i / (values.length - 1),
          size.height - ((values[i] - minValue) / range) * (size.height - strokeWidth * 2) - strokeWidth,
        ),
    ];

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }

    final fillPath = Path()..moveTo(points.first.dx, baselineY);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, baselineY)
      ..close();

    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(points.last, strokeWidth * 1.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
