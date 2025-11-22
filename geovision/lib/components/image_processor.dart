import 'dart:io';

import 'package:image/image.dart' as img; // Ensure you have this import at the top!
import 'package:flutter/foundation.dart'; // Needed for 'compute'

// ---------------------------------------------------
// 1. THE BACKGROUND WORKER
// This sits outside the class. It accepts a file path,
// makes it square, and saves it back to the same path.
// ---------------------------------------------------
Future<String> cropSquareImage(String filePath) async {
  // A. Read the file from disk
  final bytes = await File(filePath).readAsBytes();

  // B. Decode the image so we can manipulate it
  // 'decodeImage' handles JPG, PNG, etc. automatically
  final img.Image? src = img.decodeImage(bytes);

  if (src == null) return filePath; // If file is corrupt, return original

  // C. Determine the crop size (Smallest side)
  // If the image is 1080x1920, the square will be 1080x1080
  final int size = src.width < src.height ? src.width : src.height;

  // D. Calculate offsets to center the crop
  final int xOffset = (src.width - size) ~/ 2;
  final int yOffset = (src.height - size) ~/ 2;

  // E. Perform the Crop
  // cmd: copyCrop(image, x, y, width, height)
  final img.Image cropped = img.copyCrop(
      src,
      x: xOffset,
      y: yOffset,
      width: size,
      height: size
  );

  // F. Encode back to JPG (Compress slightly to save space, e.g., 90%)
  final jpgBytes = img.encodeJpg(cropped, quality: 90);

  // G. Overwrite the temporary file with the new square version
  await File(filePath).writeAsBytes(jpgBytes);

  return filePath;
}