import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageWorkerRequest {
  final String inputPath;
  final String outputPath;
  final int targetSize;
  final int minSize;

  ImageWorkerRequest(this.inputPath, this.outputPath, this.targetSize, this.minSize);
}

/// The global function used by compute()
Future<bool> backgroundSquarePad(ImageWorkerRequest request) async {
  try {
    final file = File(request.inputPath);
    final bytes = await file.readAsBytes();

    // 1. Decode
    final img.Image? src = img.decodeImage(bytes);
    if (src == null) return false;

    // 2. Resize (Fit within target box)
    final img.Image resized = img.copyResize(
        src,
        width: request.targetSize,
        height: request.targetSize,
        maintainAspect: true
    );

    // 3. Create Square Canvas (Transparent)
    final img.Image canvas = img.Image(
        width: request.targetSize,
        height: request.targetSize,
        numChannels: 4 // RGBA
    );

    // 4. Center the image
    final int dstX = (request.targetSize - resized.width) ~/ 2;
    final int dstY = (request.targetSize - resized.height) ~/ 2;
    img.compositeImage(canvas, resized, dstX: dstX, dstY: dstY);

    // 5. Encode & Write to Disk
    await File(request.outputPath).writeAsBytes(img.encodePng(canvas));

    return true;
  } catch (e) {
    debugPrint("Background Worker Error: $e");
    return false;
  }
}