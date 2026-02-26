import 'package:flutter/material.dart';
import 'annotation_layer.dart';

class LayerPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final DrawingStroke? currentStroke;
  final Offset? cursorPosition;
  final Size? imageSize;

  LayerPainter({
    required this.strokes,
    this.currentStroke,
    this.cursorPosition,
    this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    double scale = 1.0;
    if (imageSize != null) {
      scale = size.width / imageSize!.width;
      canvas.scale(scale);
    }

    // Draw saved strokes
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, isLive: false);
    }

    // Draw current live stroke
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!, isLive: true);
    }

    canvas.restore(); // Restore before drawing cursor

    if (cursorPosition != null && currentStroke != null) {
      final visualPos = cursorPosition! * scale;
      final visualRadius = (currentStroke!.width * scale) / 2;

      final cursorPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black.withValues(alpha:0.5)
        ..strokeWidth = 1.0;

      canvas.drawCircle(visualPos, visualRadius, cursorPaint);

      cursorPaint.color = Colors.white.withValues(alpha:0.5);
      canvas.drawCircle(visualPos, visualRadius - 1.0, cursorPaint);
    }
  }

  void _drawStroke(Canvas canvas, DrawingStroke stroke,{required bool isLive}) {
    final paint = Paint()
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (stroke.isEraser) {
      paint.blendMode = BlendMode.clear;
    } else {
      paint.color = stroke.color;
      paint.blendMode = BlendMode.srcOver;
    }

    // Use the live path if it exists (current session)
    if (stroke.path != null && !isLive) {
      paint.style = stroke.filled ? PaintingStyle.fill : PaintingStyle.stroke;
      canvas.drawPath(stroke.path!, paint);
      return;
    }

    // RECONSTRUCTION (After Reload)
    if (stroke.points.isNotEmpty) {
      final path = Path();
      path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      if (stroke.filled) {
        path.close();
        paint.style = PaintingStyle.fill;
      } else {
        paint.style = PaintingStyle.stroke;
      }

      if (!isLive) {
        stroke.path = path;
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LayerPainter oldDelegate) => true;
}