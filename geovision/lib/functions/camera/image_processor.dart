import 'dart:io';
import 'package:image/image.dart' as img;

Future<String> cropSquareImage(String filePath) async {
  // 1. Read the image file from disk
  final bytes = await File(filePath).readAsBytes();

  // 2. Decode the raw bytes into an editable Image object
  final img.Image? src = img.decodeImage(bytes);

  // If the file is corrupt or not an image, return the original path safely
  if (src == null) return filePath;

  // 3. Process the image (Crop & Resize)
  // 'copyResizeCropSquare' automatically finds the center, crops it to a square,
  // and resizes the result to exactly 640x640 pixels in one efficient step.
  final img.Image resized = img.copyResizeCropSquare(src, size: 640);

  final pngBytes = img.encodePng(resized);

  // 5. Overwrite the original file with the new 640x640 version
  await File(filePath).writeAsBytes(pngBytes);

  return filePath;
}


Future<String?> padToSquare(String filePath, {int targetSize = 640, int minSize = 200}) async {
  final bytes = await File(filePath).readAsBytes();
  final img.Image? src = img.decodeImage(bytes);

  if (src == null) return null;

  if (src.width < minSize || src.height < minSize) {
    return null;
  }

  final img.Image resized = img.copyResize(
      src,
      width: targetSize,
      height: targetSize,
      maintainAspect: true
  );

  // 1. Set numChannels to 4 to support Alpha (Transparency)
  final img.Image canvas = img.Image(
    width: targetSize,
    height: targetSize,
    numChannels: 4,
  );

  // 2. Fill with Transparent Color (R:0, G:0, B:0, A:0)
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final int dstX = (targetSize - resized.width) ~/ 2;
  final int dstY = (targetSize - resized.height) ~/ 2;

  img.compositeImage(canvas, resized, dstX: dstX, dstY: dstY);

  final pngBytes = img.encodePng(canvas);

  String newPath = filePath;
  if (!filePath.toLowerCase().endsWith(".png")) {
    newPath = filePath.replaceAll(RegExp(r'\.\w+$'), '.png');
    await File(filePath).delete();
  }

  await File(newPath).writeAsBytes(pngBytes);

  return newPath;
}