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

Future<String?> padToSquare(String filePath, int targetSize) async {
  try {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final img.Image? src = img.decodeImage(bytes);

    if (src == null) return null;

    // Resize
    final img.Image resized = img.copyResize(
        src, width: targetSize, height: targetSize, maintainAspect: true
    );

    // Pad
    final img.Image canvas = img.Image(
        width: targetSize, height: targetSize, numChannels: 4
    );

    // Center
    final int dstX = (targetSize - resized.width) ~/ 2;
    final int dstY = (targetSize - resized.height) ~/ 2;
    img.compositeImage(canvas, resized, dstX: dstX, dstY: dstY);

    // Save as PNG (Overwriting or creating new)
    // Note: If you want to overwrite, just use filePath.
    // Here we assume we are saving to the temp path passed in.
    return filePath; // In this specific flow, we write to file inside the loop below
  } catch (e) {
    return null;
  }
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

