import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../components/annotation/annotation_layer.dart';

class CocoConversionService {
  static Future<Map<String, dynamic>?> generateAnnotationForLayer({
    required AnnotationLayer layer,
    required Size imageSize,
    required int imageId,
    required int annotationId,
    required int categoryId,
  }) async {
    if (layer.strokes.isEmpty) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, imageSize.width, imageSize.height));

    // 1. RENDER ALL STROKES TO THE MASK
    for (final stroke in layer.strokes) {
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (stroke.isEraser) {
        paint.blendMode = BlendMode.clear;
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = stroke.width;
      } else {
        paint.color = const Color(0xFFFFFFFF);
        paint.blendMode = BlendMode.srcOver;
      }

      if (stroke.path != null) {
        paint.style = PaintingStyle.fill;
        canvas.drawPath(stroke.path!, paint);
      } else if (stroke.points.isNotEmpty) {
        paint.strokeWidth = stroke.width;
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
        canvas.drawPath(path, paint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(imageSize.width.toInt(), imageSize.height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();

    if (byteData == null) return null;

    // 2. TRACE ALL DISJOINT SHAPES (Multi-Contour)
    final List<List<double>> allPolygons = _traceAllContours(
        byteData.buffer.asUint8List(),
        imageSize.width.toInt(),
        imageSize.height.toInt()
    );

    if (allPolygons.isEmpty) return null;

    // 3. CALCULATE GLOBAL BBOX
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (var polygon in allPolygons) {
      for (int i = 0; i < polygon.length; i += 2) {
        if (polygon[i] < minX) minX = polygon[i];
        if (polygon[i+1] < minY) minY = polygon[i+1];
        if (polygon[i] > maxX) maxX = polygon[i];
        if (polygon[i+1] > maxY) maxY = polygon[i+1];
      }
    }

    return {
      "id": annotationId,
      "image_id": imageId,
      "category_id": categoryId,
      "bbox": [minX, minY, maxX - minX, maxY - minY],
      "segmentation": allPolygons, // Array of multiple polygon paths
      "area": (maxX - minX) * (maxY - minY),
      "iscrowd": 0
    };
  }

  static List<List<double>> _traceAllContours(Uint8List pixels, int width, int height) {
    List<List<double>> allContours = [];
    // We work on a copy because we need to "erase" pixels as we find them
    Uint8List workingPixels = Uint8List.fromList(pixels);

    while (true) {
      int startX = -1;
      int startY = -1;

      // Scan for the next visible pixel
      outer:
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          if (_getPixelFromList(workingPixels, width, x, y) > 0) {
            startX = x;
            startY = y;
            break outer;
          }
        }
      }

      if (startX == -1) break; // No more shapes

      // Trace the found shape
      final contour = _traceSingleContour(workingPixels, width, height, startX, startY);

      if (contour.length >= 6) {
        allContours.add(contour);
      }

      // Erase this component so it's not detected again
      _floodErase(workingPixels, width, height, startX, startY);
    }
    return allContours;
  }

  static void _floodErase(Uint8List pixels, int width, int height, int x, int y) {
    final queue = <List<int>>[[x, y]];
    while (queue.isNotEmpty) {
      final curr = queue.removeLast();
      final cx = curr[0];
      final cy = curr[1];

      if (cx < 0 || cx >= width || cy < 0 || cy >= height) continue;
      final idx = (cy * width + cx) * 4 + 3;

      if (pixels[idx] > 0) {
        pixels[idx] = 0; // Erase alpha
        queue.add([cx + 1, cy]);
        queue.add([cx - 1, cy]);
        queue.add([cx, cy + 1]);
        queue.add([cx, cy - 1]);
      }
    }
  }

  static List<double> _traceSingleContour(Uint8List pixels, int width, int height, int startX, int startY) {
    List<double> contour = [startX.toDouble(), startY.toDouble()];
    int currentX = startX;
    int currentY = startY;
    int backtrackX = startX - 1;
    int backtrackY = startY;

    int pointsFound = 0;
    while (pointsFound < (width * height)) {
      var next = _findNextNeighbor(pixels, width, height, currentX, currentY, backtrackX, backtrackY);
      if (next == null) break;

      currentX = next[0];
      currentY = next[1];
      backtrackX = next[2];
      backtrackY = next[3];

      if (pointsFound % 2 == 0) { // Slight optimization
        contour.add(currentX.toDouble());
        contour.add(currentY.toDouble());
      }
      pointsFound++;
      if (currentX == startX && currentY == startY) break;
    }
    return contour;
  }

  static int _getPixelFromList(Uint8List pixels, int width, int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= (pixels.length / (width * 4))) return 0;
    return pixels[(y * width + x) * 4 + 3];
  }

  static List<int>? _findNextNeighbor(Uint8List pixels, int w, int h, int cx, int cy, int bx, int by) {
    final neighbors = [[-1, 0], [-1, -1], [0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1]];
    int dx = bx - cx;
    int dy = by - cy;
    int startIndex = 0;
    for (int i = 0; i < 8; i++) {
      if (neighbors[i][0] == dx && neighbors[i][1] == dy) {
        startIndex = i;
        break;
      }
    }

    for (int i = 0; i < 8; i++) {
      int idx = (startIndex + i) % 8;
      int nx = cx + neighbors[idx][0];
      int ny = cy + neighbors[idx][1];
      if (_getPixelFromList(pixels, w, nx, ny) > 0) {
        int backIdx = (idx - 1 + 8) % 8;
        return [nx, ny, cx + neighbors[backIdx][0], cy + neighbors[backIdx][1]];
      }
    }
    return null;
  }
}