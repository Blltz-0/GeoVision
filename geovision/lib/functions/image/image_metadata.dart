import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';

class ImageMetadata {
  // --- METADATA (EXIF) OPS ---

  static Future<Map<String, Object>?> readMetadata(String path) async {
    try {
      final exif = await Exif.fromPath(path);
      final latLong = await exif.getLatLong();
      final originalDate = await exif.getAttribute('DateTimeOriginal');
      final digitizedDate = await exif.getAttribute('DateTimeDigitized');
      await exif.close();

      Map<String, Object> data = {};
      if (latLong != null) {
        data['lat'] = latLong.latitude;
        data['lng'] = latLong.longitude;
      }
      if (originalDate != null) data['DateTimeOriginal'] = originalDate;
      if (digitizedDate != null) data['DateTimeDigitized'] = digitizedDate;

      return data.isNotEmpty ? data : null;
    } catch (e) {
      return null; // Fail silently for metadata
    }
  }

  static Future<void> writeMetadata(String path, Map<String, Object>? metadata) async {
    if (metadata == null) return;
    try {
      final exif = await Exif.fromPath(path);
      Map<String, Object> attributes = {};

      if (metadata.containsKey('lat') && metadata.containsKey('lng')) {
        double lat = metadata['lat'] as double;
        double lng = metadata['lng'] as double;
        attributes['GPSLatitude'] = lat.abs();
        attributes['GPSLatitudeRef'] = lat >= 0 ? 'N' : 'S';
        attributes['GPSLongitude'] = lng.abs();
        attributes['GPSLongitudeRef'] = lng >= 0 ? 'E' : 'W';
      }
      if (metadata.containsKey('DateTimeOriginal')) {
        attributes['DateTimeOriginal'] = metadata['DateTimeOriginal']!;
      }
      await exif.writeAttributes(attributes);
      await exif.close();
    } catch (e) {
      debugPrint("Error restoring metadata: $e");
    }
  }

  // --- HISTORY JSON OPS ---

  static Future<File> _getHistoryFile(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final historyFile = File('${appDir.path}/projects/$projectName/upload_history.json');
    if (!await historyFile.exists()) {
      await historyFile.create(recursive: true);
      await historyFile.writeAsString(jsonEncode({}));
    }
    return historyFile;
  }

  static Future<Map<String, dynamic>> loadUploadHistory(String projectName) async {
    try {
      final file = await _getHistoryFile(projectName);
      final String content = await file.readAsString();
      final dynamic decoded = jsonDecode(content);

      if (decoded is List) return {};

      // Backward compatibility logic
      Map<String, dynamic> result = {};
      decoded.forEach((key, value) {
        if (value is String) {
          result[key] = {'originalName': value, 'size': -1};
        } else {
          result[key] = value;
        }
      });
      return result;
    } catch (e) {
      return {};
    }
  }

  static Future<void> saveUploadHistory(String projectName, Map<String, dynamic> history) async {
    try {
      final file = await _getHistoryFile(projectName);
      await file.writeAsString(jsonEncode(history));
    } catch (e) {
      debugPrint("Error saving history: $e");
    }
  }
}