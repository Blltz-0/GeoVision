import 'package:flutter/foundation.dart';
import 'package:native_exif/native_exif.dart';

class MetadataExif {
  // --- EMBED METADATA ---
  static Future<void> embedMetadata({
    required String filePath,
    required double lat,
    required double lng,
    String? className,
    DateTime? time,
    bool updateClassOnly = false,
  }) async {
    try {
      final exif = await Exif.fromPath(filePath);
      Map<String, Object> attributes = {};

      if (!updateClassOnly) {
        attributes['GPSLatitude'] = lat.abs();
        attributes['GPSLatitudeRef'] = lat >= 0 ? 'N' : 'S';
        attributes['GPSLongitude'] = lng.abs();
        attributes['GPSLongitudeRef'] = lng >= 0 ? 'E' : 'W';
      }

      if (className != null && className.isNotEmpty) {
        attributes['UserComment'] = className;
      }

      if (time != null) {
        String formattedDate =
            "${time.year}:${time.month.toString().padLeft(2, '0')}:${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}";
        attributes['DateTimeOriginal'] = formattedDate;
        attributes['DateTimeDigitized'] = formattedDate;
      }

      await exif.writeAttributes(attributes);
      await exif.close();
    } catch (e) {
      debugPrint("⚠️ EXIF Error: $e");
    }
  }

  static Future<Map<String, double>?> getLatLong(String path) async {
    try {
      final exif = await Exif.fromPath(path);
      final latLong = await exif.getLatLong();
      await exif.close();
      if (latLong != null) {
        return {'lat': latLong.latitude, 'lng': latLong.longitude};
      }
    } catch (e) {
      debugPrint("⚠️ EXIF Read Error for $path: $e");
    }
    return null;
  }
}