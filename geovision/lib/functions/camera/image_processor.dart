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
  // and resizes the result to exactly 630x630 pixels in one efficient step.
  final img.Image resized = img.copyResizeCropSquare(src, size: 630);

  // 4. Encode the new image back to JPG
  // We use 90% quality to save space while maintaining high visual fidelity.
  final jpgBytes = img.encodeJpg(resized, quality: 90);

  // 5. Overwrite the original file with the new 630x630 version
  await File(filePath).writeAsBytes(jpgBytes);

  return filePath;
}