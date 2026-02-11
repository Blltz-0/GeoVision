import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:native_exif/native_exif.dart'; // Required for metadata preservation

Future<String> cropSquareImage(String filePath) async {
  // 1. PRESERVE METADATA (Read before processing)
  Map<String, Object>? preservedMetadata = await _readMetadata(filePath);

  // 2. Read the image file from disk
  final bytes = await File(filePath).readAsBytes();
  final img.Image? src = img.decodeImage(bytes);

  if (src == null) return filePath;

  // 3. Process (Crop & Resize)
  final img.Image resized = img.copyResizeCropSquare(src, size: 640);
  final pngBytes = img.encodePng(resized);

  // 4. Overwrite original
  await File(filePath).writeAsBytes(pngBytes);

  // 5. RESTORE METADATA (Write back to the file)
  await _writeMetadata(filePath, preservedMetadata);

  return filePath;
}

Future<String?> padToSquare(String filePath, {int targetSize = 640, int minSize = 200}) async {
  // 1. PRESERVE METADATA (Read before processing)
  // We must do this before the file potentially gets deleted or overwritten
  Map<String, Object>? preservedMetadata = await _readMetadata(filePath);

  final bytes = await File(filePath).readAsBytes();
  final img.Image? src = img.decodeImage(bytes);

  if (src == null) return null;

  if (src.width < minSize || src.height < minSize) {
    return null;
  }

  // 2. Process Image (Resize & Pad)
  final img.Image resized = img.copyResize(
      src,
      width: targetSize,
      height: targetSize,
      maintainAspect: true
  );

  final img.Image canvas = img.Image(
    width: targetSize,
    height: targetSize,
    numChannels: 4,
  );

  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final int dstX = (targetSize - resized.width) ~/ 2;
  final int dstY = (targetSize - resized.height) ~/ 2;

  img.compositeImage(canvas, resized, dstX: dstX, dstY: dstY);
  final pngBytes = img.encodePng(canvas);

  // 3. Handle File Path (JPG -> PNG conversion)
  String newPath = filePath;
  if (!filePath.toLowerCase().endsWith(".png")) {
    newPath = filePath.replaceAll(RegExp(r'\.\w+$'), '.png');
    // We delete the old file, which is why we read metadata in step 1
    try {
      if (await File(filePath).exists()) {
        await File(filePath).delete();
      }
    } catch (e) {
      // Ignore delete errors
    }
  }

  // 4. Save New Image
  await File(newPath).writeAsBytes(pngBytes);

  // 5. RESTORE METADATA
  await _writeMetadata(newPath, preservedMetadata);

  return newPath;
}



Future<Map<String, Object>?> _readMetadata(String path) async {
  try {
    final exif = await Exif.fromPath(path);
    final latLong = await exif.getLatLong();
    final originalDate = await exif.getAttribute('DateTimeOriginal');
    final digitizedDate = await exif.getAttribute('DateTimeDigitized');
    await exif.close();

    Map<String, Object> data = {};

    // Store Location
    if (latLong != null) {
      data['lat'] = latLong.latitude;
      data['lng'] = latLong.longitude;
    }

    // Store Time
    if (originalDate != null) data['DateTimeOriginal'] = originalDate;
    if (digitizedDate != null) data['DateTimeDigitized'] = digitizedDate;

    return data.isNotEmpty ? data : null;
  } catch (e) {
    print("Error reading metadata: $e");
    return null;
  }
}

Future<void> _writeMetadata(String path, Map<String, Object>? metadata) async {
  if (metadata == null) return;

  try {
    final exif = await Exif.fromPath(path);
    Map<String, Object> attributes = {};

    // Restore Location
    if (metadata.containsKey('lat') && metadata.containsKey('lng')) {
      double lat = metadata['lat'] as double;
      double lng = metadata['lng'] as double;

      attributes['GPSLatitude'] = lat.abs();
      attributes['GPSLatitudeRef'] = lat >= 0 ? 'N' : 'S';
      attributes['GPSLongitude'] = lng.abs();
      attributes['GPSLongitudeRef'] = lng >= 0 ? 'E' : 'W';
    }

    // Restore Time
    if (metadata.containsKey('DateTimeOriginal')) {
      attributes['DateTimeOriginal'] = metadata['DateTimeOriginal']!;
    }
    if (metadata.containsKey('DateTimeDigitized')) {
      attributes['DateTimeDigitized'] = metadata['DateTimeDigitized']!;
    }

    await exif.writeAttributes(attributes);
    await exif.close();
  } catch (e) {
    if (kDebugMode) {
      print("Error writing metadata back: $e");
    }
  }
}