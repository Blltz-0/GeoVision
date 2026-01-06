import 'package:flutter/material.dart';
import 'annotation_layer.dart';

class LayerPainter extends CustomPainter {
  final List<DrawingStroke> strokes;

  // New: The stroke currently being drawn (not saved to list yet)
  final DrawingStroke? currentStroke;

  // New: Where to draw the brush cursor
  final Offset? cursorPosition;

  LayerPainter({
    required this.strokes,
    this.currentStroke,
    this.cursorPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Create a compositing layer.
    // This isolates blending modes (like Clear) to this specific AnnotationLayer.
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // 2. Draw all saved strokes
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    // 3. Draw the stroke currently being dragged (Real-time feedback)
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
    }

    // 4. Restore layer (applies the ink/eraser to the canvas)
    canvas.restore();

    // 5. Draw the Cursor (Pointer) on TOP of everything
    // We draw this *after* restore so the eraser doesn't eat the cursor itself.
    if (cursorPosition != null && currentStroke != null) {
      final cursorPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black.withValues(alpha:0.5) // Semi-transparent black ring
        ..strokeWidth = 1.0;

      // Draw outer ring
      canvas.drawCircle(cursorPosition!, currentStroke!.width / 2, cursorPaint);

      // Draw inner white ring (for contrast on dark images)
      cursorPaint.color = Colors.white.withValues(alpha:0.5);
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
      // Standard blending for paint
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
  bool shouldRepaint(covariant LayerPainter oldDelegate) {
    return true; // Always repaint to animate cursor/strokes
  }
}