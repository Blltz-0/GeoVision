import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../components/annotation_layer.dart'; // Import your models
import '../components/layer_painter.dart';   // Import your painter

class CocoConversionService {

  /// Main function to convert a single layer into a COCO Annotation Map
  static Future<Map<String, dynamic>?> generateAnnotationForLayer({
    required AnnotationLayer layer,
    required Size imageSize,
    required int imageId,
    required int annotationId,
    required int categoryId,
  }) async {
    if (layer.strokes.isEmpty) return null;

    // 1. Rasterize: Draw the strokes onto an invisible canvas
    final Uint8List? maskBytes = await _renderLayerToBytes(layer, imageSize);

    if (maskBytes == null) return null;

    // 2. Analyze: Calculate BBox and RLE from the bytes
    final result = _calculateBBoxAndRLE(maskBytes, imageSize.width.toInt(), imageSize.height.toInt());

    // If the layer is empty (user erased everything), result is null
    if (result == null) return null;

    return {
      "id": annotationId,
      "image_id": imageId,
      "category_id": categoryId,
      "bbox": result['bbox'],         // [x, y, width, height]
      "segmentation": result['rle'],  // COCO RLE Format
      "area": result['area'],         // Pixel count area
      "iscrowd": 1                    // 1 = RLE/Mask, 0 = Polygon
    };
  }

  // --- INTERNAL: Renders the layer to raw RGBA bytes ---
  static Future<Uint8List?> _renderLayerToBytes(AnnotationLayer layer, Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));

    // We rely on your existing LayerPainter!
    // We force all colors to WHITE for the mask, so logic is simple (Is it white? Yes/No)
    final whiteStrokes = layer.strokes.map((s) {
      if (s.isEraser) return s; // Keep erasers as they are
      return s.copyWith(color: const Color(0xFFFFFFFF)); // Force White
    }).toList();

    final painter = LayerPainter(strokes: whiteStrokes);
    painter.paint(canvas, size);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.width.toInt(), size.height.toInt());

    // Get Raw RGBA Data
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    return byteData?.buffer.asUint8List();
  }

  // --- INTERNAL: Calculates BBox and RLE ---
  static Map<String, dynamic>? _calculateBBoxAndRLE(Uint8List bytes, int width, int height) {
    // 1. Calculate BBox
    int minX = width;
    int minY = height;
    int maxX = 0;
    int maxY = 0;
    int area = 0;
    bool foundAny = false;

    // Standard scan for BBox (Row-Major is fine for BBox)
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // RGBA = 4 bytes. We check Red channel (index 0).
        // Since we drew White (255, 255, 255), if Red > 128, it's part of the mask.
        int index = (y * width + x) * 4;
        if (bytes[index] > 128) { // Threshold
          foundAny = true;
          area++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (!foundAny) return null;

    final bbox = [
      minX.toDouble(),
      minY.toDouble(),
      (maxX - minX + 1).toDouble(),
      (maxY - minY + 1).toDouble(),
    ];

    // 2. Calculate RLE (Run-Length Encoding)
    // CRITICAL: COCO RLE is Column-Major (Scan down x=0, then x=1...)
    List<int> counts = [];
    bool isInsideObject = false;
    int currentRun = 0;

    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        int index = (y * width + x) * 4;
        bool isPixelActive = bytes[index] > 128; // Check Red channel

        if (isPixelActive == isInsideObject) {
          // Continuing the same run (e.g., still black, or still white)
          currentRun++;
        } else {
          // Switch happened! Record count and flip state.
          counts.add(currentRun);
          currentRun = 1;
          isInsideObject = !isInsideObject;
        }
      }
    }
    counts.add(currentRun); // Add final run

    final rle = {
      "counts": counts,
      "size": [height, width] // COCO format expects [height, width]
    };

    return {
      "bbox": bbox,
      "rle": rle,
      "area": area
    };
  }
}