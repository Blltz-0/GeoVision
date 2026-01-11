import 'package:flutter/material.dart';
import 'annotation_layer.dart'; // Adjust import path if needed

class LayerPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final DrawingStroke? currentStroke;
  final Offset? cursorPosition;

  LayerPainter({
    required this.strokes,
    this.currentStroke,
    this.cursorPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
    }

    canvas.restore();

    // Draw Cursor
    if (cursorPosition != null && currentStroke != null) {
      final cursorPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black.withOpacity(0.5)
        ..strokeWidth = 1.0;

      canvas.drawCircle(cursorPosition!, currentStroke!.width / 2, cursorPaint);

      cursorPaint.color = Colors.white.withOpacity(0.5);
      canvas.drawCircle(cursorPosition!, (currentStroke!.width / 2) - 1.0, cursorPaint);
    }
  }

  void _drawStroke(Canvas canvas, DrawingStroke stroke) {
    final paint = Paint()
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.isEraser) {
      paint.blendMode = BlendMode.clear;
    } else {
      paint.color = stroke.color;
      paint.blendMode = BlendMode.srcOver;
    }

    if (stroke.points.isNotEmpty) {
      final path = Path();
      path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LayerPainter oldDelegate) => true;
}