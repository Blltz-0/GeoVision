import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../components/annotation_layer.dart';

class CocoConversionService {

  static Future<Map<String, dynamic>?> generateAnnotationForLayer({
    required AnnotationLayer layer,
    required Size imageSize,
    required int imageId,
    required int annotationId,
    required int categoryId,
  }) async {
    if (layer.strokes.isEmpty) return null;

    // 1. RENDER MASK TO MEMORY
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, imageSize.width, imageSize.height));

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in layer.strokes) {
      if (stroke.isEraser) continue; // Ignore erasers for shape tracing

      paint.strokeWidth = stroke.width;
      paint.color = const Color(0xFFFFFFFF); // White paint

      final path = Path();
      if (stroke.points.isNotEmpty) {
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(imageSize.width.toInt(), imageSize.height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData == null) return null;

    // 2. TRACE CONTOUR (Algorithm: Moore-Neighbor Tracing)
    final points = _traceContour(byteData, imageSize.width.toInt(), imageSize.height.toInt());

    img.dispose(); // Free memory

    // If no shape found, skip
    if (points.isEmpty || points.length < 6) return null;

    // 3. CALCULATE BBOX FROM POLYGON
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (int i = 0; i < points.length; i += 2) {
      double x = points[i];
      double y = points[i+1];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    final bbox = [
      minX,
      minY,
      maxX - minX,
      maxY - minY
    ];

    final area = bbox[2] * bbox[3];

    return {
      "id": annotationId,
      "image_id": imageId,
      "category_id": categoryId,
      "bbox": bbox,

      // POLYGON: This is what MakeSense needs to see the shape
      "segmentation": [points],

      "area": area,
      "iscrowd": 0
    };
  }

  // --- CONTOUR TRACING ALGORITHM ---
  static List<double> _traceContour(ByteData data, int width, int height) {
    List<double> contour = [];

    // Step A: Find Starting Pixel (Top-Left most visible pixel)
    int startX = -1;
    int startY = -1;

    // Loop Y then X to find first non-transparent pixel
    outerLoop:
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (_getPixel(data, width, x, y) > 0) {
          startX = x;
          startY = y;
          break outerLoop;
        }
      }
    }

    if (startX == -1) return []; // Canvas is empty

    // Step B: Moore-Neighbor Tracing
    // We walk around the edge of the pixels
    contour.add(startX.toDouble());
    contour.add(startY.toDouble());

    int currentX = startX;
    int currentY = startY;
    // Enter from West (Left)
    int backtrackX = startX - 1;
    int backtrackY = startY;

    // Safety Loop limit prevents infinite loop if algorithm gets stuck
    int maxPoints = width * height;
    int pointsFound = 0;

    while (pointsFound < maxPoints) {
      // Find next boundary pixel by checking 8 neighbors clockwise
      var next = _findNextNeighbor(data, width, height, currentX, currentY, backtrackX, backtrackY);

      if (next == null) break; // Isolated pixel

      int nextX = next[0];
      int nextY = next[1];

      // Update Backtrack (previous empty spot)
      // For Moore algo, the backtrack is the neighbor immediately before the one we found
      backtrackX = next[2];
      backtrackY = next[3];

      // Add to list (Simple optimization: Skip every 2nd point to reduce file size)
      if (pointsFound % 3 == 0) {
        contour.add(nextX.toDouble());
        contour.add(nextY.toDouble());
      }

      currentX = nextX;
      currentY = nextY;
      pointsFound++;

      // Stop if we return to start
      if (currentX == startX && currentY == startY) break;
    }

    return contour;
  }

  // Helper to get pixel Alpha value (0-255)
  static int _getPixel(ByteData data, int width, int x, int y) {
    if (x < 0 || x >= width || y < 0) return 0;
    // RGBA: Alpha is offset + 3
    final index = (y * width + x) * 4 + 3;
    if (index >= data.lengthInBytes) return 0;
    return data.getUint8(index);
  }

  // Scans 8 neighbors clockwise to find the edge
  static List<int>? _findNextNeighbor(ByteData data, int w, int h, int cx, int cy, int bx, int by) {
    // Clockwise Offsets relative to center (starting from West/Left)
    final neighbors = [
      [-1, 0], [-1, -1], [0, -1], [1, -1],
      [1, 0], [1, 1], [0, 1], [-1, 1]
    ];

    // Determine start index based on backtrack direction
    int dx = bx - cx;
    int dy = by - cy;
    int startIndex = -1;

    for(int i=0; i<8; i++) {
      if (neighbors[i][0] == dx && neighbors[i][1] == dy) {
        startIndex = i;
        break;
      }
    }

    if (startIndex == -1) startIndex = 0;

    // Scan clockwise from backtrack position
    for (int i = 0; i < 8; i++) {
      int idx = (startIndex + i) % 8; // Wrap around
      int nx = cx + neighbors[idx][0];
      int ny = cy + neighbors[idx][1];

      if (_getPixel(data, w, nx, ny) > 0) {
        // Found the next pixel!
        // The backtrack for next step is the neighbor *before* this one (idx - 1)
        int backIdx = (idx - 1 + 8) % 8;
        int newBx = cx + neighbors[backIdx][0];
        int newBy = cy + neighbors[backIdx][1];

        return [nx, ny, newBx, newBy];
      }
    }
    return null; // Dead end
  }
}