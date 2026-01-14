import 'package:flutter/material.dart';
import 'annotation_layer.dart';

class LayerPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final DrawingStroke? currentStroke;
  final Offset? cursorPosition;
  final Size? imageSize; // <--- NEW: We need the original image dimensions

  LayerPainter({
    required this.strokes,
    this.currentStroke,
    this.cursorPosition,
    this.imageSize, // <--- Add to constructor
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    // --- THE FIX: SCALING ---
    // If we know the original image size, we scale the canvas
    // to match the current display size.
    // Example: Image is 1000px, Screen is 500px -> Scale = 0.5
    double scale = 1.0;
    if (imageSize != null) {
      scale = size.width / imageSize!.width;
      canvas.scale(scale);
    }

    // Draw saved strokes
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    // Draw current live stroke
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
    }

    canvas.restore(); // Restore before drawing cursor (cursor is usually screen-space)

    // Draw Cursor (Optional: keep this in screen space or scale it too)
    if (cursorPosition != null && currentStroke != null) {
      // For the cursor, we want it to follow the finger visually
      // We calculate the visual position manually since we popped the canvas.save()
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