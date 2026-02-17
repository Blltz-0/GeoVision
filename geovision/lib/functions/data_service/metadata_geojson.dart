import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'file_directories.dart';
import 'metadata_exif.dart';

class MetadataGeoJson {
  // --- 1. REBUILD DATABASE (The "Smart" Sync - Preserves Data) ---
  static Future<void> rebuildProjectData(String projectName, {String projectType = 'classification'}) async {
    final projectDir = await FileDirectories.getProjectImageDir(projectName);
    final geoFile = await FileDirectories.getGeoJsonFile(projectName);
    final classFile = await FileDirectories.getClassFile(projectName);

    if (!await projectDir.exists()) return;

    // 1. Load EXISTING GeoJSON to preserve metadata (The Fix)
    Map<String, Map<String, dynamic>> existingData = {};
    if (await geoFile.exists()) {
      try {
        final content = await geoFile.readAsString();
        if (content.isNotEmpty) {
          final json = jsonDecode(content);
          if (json['features'] != null) {
            for (var f in json['features']) {
              // We use filename as the key to map data back
              String rawPath = f['properties']['path'] ?? "";
              String name = p.basename(rawPath);
              existingData[name] = f;
            }
          }
        }
      } catch (e) {
        debugPrint("Error reading existing GeoJSON: $e");
      }
    }

    // 2. Load Valid Classes
    Set<String> validClasses = {'Unclassified'};
    if (await classFile.exists()) {
      try {
        List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
        for (var item in jsonList) {
          validClasses.add(item['name']);
        }
      } catch (_) {}
    }

    // 3. Scan Files
    List<FileSystemEntity> entities = await projectDir.list().toList();
    List<Map<String, dynamic>> features = [];

    for (var entity in entities) {
      if (entity is! File) continue;
      String path = entity.path;
      String filename = p.basename(path);

      if (!filename.toLowerCase().endsWith('.jpg') &&
          !filename.toLowerCase().endsWith('.png') &&
          !filename.toLowerCase().endsWith('.jpeg')) {
        continue;
      }

      // --- CRITICAL FIX: CHECK EXISTING DATA FIRST ---
      Map<String, dynamic>? existingFeature = existingData[filename];

      String finalClass = "Unclassified";
      double lat = 0.0;
      double lng = 0.0;
      String time = entity.lastModifiedSync().toIso8601String();

      // CASE A: We have data in GeoJSON already. Use it!
      if (existingFeature != null) {
        var coords = existingFeature['geometry']['coordinates'];
        var props = existingFeature['properties'];

        // Preserve location
        if (coords != null && coords.length >= 2) {
          lng = (coords[0] as num).toDouble();
          lat = (coords[1] as num).toDouble();
        }

        // Preserve class & time
        if (props['class'] != null) finalClass = props['class'];
        if (props['time'] != null) time = props['time'];
      }
      // CASE B: New file, try to extract metadata
      else {
        // Try filename parsing for class
        if (projectType == 'classification') {
          List<String> parts = filename.split('_');
          if (parts.length >= 2) {
            String candidate = parts[1];
            if (validClasses.contains(candidate)) {
              finalClass = candidate;
            }
          }
        }

        // Try EXIF for location
        final latLong = await MetadataExif.getLatLong(path);
        if (latLong != null) {
          lat = latLong['lat']!;
          lng = latLong['lng']!;
        }
      }

      // 4. Construct Feature
      features.add({
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [lng, lat]
        },
        "properties": {
          "path": path,
          "class": projectType == 'segmentation' ? "" : finalClass,
          "time": time,
        }
      });
    }

    final geoJson = {
      "type": "FeatureCollection",
      "features": features,
    };

    await geoFile.writeAsString(jsonEncode(geoJson));
    debugPrint("✅ GeoJSON Database Rebuilt (Preserved ${existingData.length} records) for $projectName");
  }

  // --- 2. SAVE TO DATABASE (Append/Update GeoJSON) ---
  static Future<void> saveToCsv({
    required String projectName,
    required String imagePath,
    required Position? position,
    String? className,
    String projectType = 'classification',
    DateTime? customTime, // Added support for custom time
  }) async {
    FileDirectories.saveLock = FileDirectories.saveLock.then((_) async {
      final geoFile = await FileDirectories.getGeoJsonFile(projectName);

      if (!await geoFile.parent.exists()) {
        await geoFile.parent.create(recursive: true);
      }

      Map<String, dynamic> geoData;
      if (await geoFile.exists()) {
        try {
          String content = await geoFile.readAsString();
          geoData = content.isEmpty ? {"type": "FeatureCollection", "features": []} : jsonDecode(content);
        } catch (e) {
          geoData = {"type": "FeatureCollection", "features": []};
        }
      } else {
        geoData = {"type": "FeatureCollection", "features": []};
      }

      final double lat = position?.latitude ?? 0.0;
      final double lng = position?.longitude ?? 0.0;
      // Use custom time if provided (from upload), else now
      final String timestamp = (customTime ?? DateTime.now()).toLocal().toIso8601String();
      final String finalClass = (className ?? 'Unclassified').replaceAll(',', '');

      // Check if file already exists to prevent duplicates
      List<dynamic> features = geoData['features'];
      String filename = p.basename(imagePath);
      features.removeWhere((f) => p.basename(f['properties']['path'] ?? "") == filename);

      features.add({
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [lng, lat]
        },
        "properties": {
          "path": imagePath,
          "class": projectType == 'segmentation' ? "" : finalClass,
          "time": timestamp,
        }
      });

      await geoFile.writeAsString(jsonEncode(geoData));
    });
    await FileDirectories.saveLock;
  }

  // --- 3. READ DATA ---
  static Future<List<Map<String, dynamic>>> readCsvData(String projectName) async {
    final geoFile = await FileDirectories.getGeoJsonFile(projectName);
    final projectDir = await FileDirectories.getProjectImageDir(projectName);

    List<Map<String, dynamic>> dataPoints = [];

    if (await geoFile.exists()) {
      try {
        final Map<String, dynamic> geoJson = jsonDecode(await geoFile.readAsString());
        final List features = geoJson['features'] ?? [];

        for (var feature in features) {
          final props = feature['properties'] ?? {};
          final geometry = feature['geometry'] ?? {};
          final coords = geometry['coordinates'] ?? [0.0, 0.0];

          // Reconstruct path to handle app sandbox changes (UUID changes on restart)
          String rawPath = props['path'] ?? "";
          String filename = p.basename(rawPath);
          String currentValidPath = '${projectDir.path}/$filename';

          dataPoints.add({
            "path": currentValidPath,
            "class": props['class'] ?? "Unclassified",
            "lat": (coords[1] as num).toDouble(),
            "lng": (coords[0] as num).toDouble(),
            "time": props['time'] ?? "",
          });
        }
      } catch (e) {
        debugPrint("❌ Error reading GeoJSON: $e");
      }
    }
    return dataPoints;
  }

  // --- 5. REMOVE SINGLE ENTRY ---
  static Future<void> removeEntry(String projectName, String filename) async {
    final geoFile = await FileDirectories.getGeoJsonFile(projectName);

    if (await geoFile.exists()) {
      try {
        final Map<String, dynamic> geoJson = jsonDecode(await geoFile.readAsString());
        final List features = geoJson['features'];

        features.removeWhere((f) {
          String path = f['properties']['path'] ?? "";
          return p.basename(path) == filename;
        });

        await geoFile.writeAsString(jsonEncode(geoJson));
      } catch (e) {
        debugPrint("Error removing entry: $e");
      }
    }
  }

  // --- 6. UPDATE SINGLE CLASS ---
  static Future<void> updateClassInCsv({
    required String projectName,
    required String imagePath,
    required String newClassName,
  }) async {
    final geoFile = await FileDirectories.getGeoJsonFile(projectName);
    String filename = p.basename(imagePath);

    if (await geoFile.exists()) {
      final Map<String, dynamic> geoJson = jsonDecode(await geoFile.readAsString());
      final List features = geoJson['features'];

      for (var f in features) {
        String fName = p.basename(f['properties']['path'] ?? "");
        if (fName == filename) {
          f['properties']['class'] = newClassName;
        }
      }
      await geoFile.writeAsString(jsonEncode(geoJson));
    }
  }

  // --- 7. UPDATE IMAGE METADATA ---
  static Future<void> updateImageMetadata({
    required String projectName,
    required String imagePath,
    required double lat,
    required double lng,
    required DateTime time,
    String projectType = 'classification',
  }) async {
    final geoFile = await FileDirectories.getGeoJsonFile(projectName);
    String filename = p.basename(imagePath);

    if (await geoFile.exists()) {
      final Map<String, dynamic> geoJson = jsonDecode(await geoFile.readAsString());
      final List features = geoJson['features'];

      for (var f in features) {
        String fName = p.basename(f['properties']['path'] ?? "");
        if (fName == filename) {
          f['geometry']['coordinates'] = [lng, lat];
          f['properties']['time'] = time.toIso8601String();
        }
      }
      await geoFile.writeAsString(jsonEncode(geoJson));
    }

    await MetadataExif.embedMetadata(
      filePath: imagePath,
      lat: lat,
      lng: lng,
      time: time,
    );
  }

  static Future<void> bulkUpdateCsvClass(String projectName, String targetClass, String newClassValue) async {
    final geoFile = await FileDirectories.getGeoJsonFile(projectName);
    if (!await geoFile.exists()) return;

    final Map<String, dynamic> geoJson = jsonDecode(await geoFile.readAsString());
    final List features = geoJson['features'];
    bool changed = false;

    for (var f in features) {
      if (f['properties']['class'] == targetClass) {
        f['properties']['class'] = newClassValue;
        changed = true;
      }
    }

    if (changed) {
      await geoFile.writeAsString(jsonEncode(geoJson));
    }
  }
}