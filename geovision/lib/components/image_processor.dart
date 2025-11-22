import 'dart:io';
import 'package:image/image.dart' as img;

Future<String> cropSquareImage(String filePath) async {
  // A. Read the file from disk
  final bytes = await File(filePath).readAsBytes();

  // B. Decode the image so we can manipulate it
  final img.Image? src = img.decodeImage(bytes);

  if (src == null) return filePath; // If file is corrupt, return original

  // C. Determine the crop size (Smallest side)
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