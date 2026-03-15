import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'file_directories.dart';
import 'metadata_exif.dart';

class MetadataGeoJson {
  // --- 1. REBUILD DATABASE (Uses Filenames only) ---
  static Future<void> rebuildProjectData(String projectName, {String projectType = 'classification'}) async {
    final projectDir = await FileDirectories.getProjectImageDir(projectName);
    final geoFile = await FileDirectories.getGeoJsonFile(projectName);
    final classFile = await FileDirectories.getClassFile(projectName);

    if (!await projectDir.exists()) return;

    Map<String, Map<String, dynamic>> existingData = {};
    if (await geoFile.exists()) {
      try {
        final content = await geoFile.readAsString();
        if (content.isNotEmpty) {
          final json = jsonDecode(content);
          if (json['features'] != null) {
            for (var f in json['features']) {
              // FIX: Rescue files that were corrupted by the old 'name' key
              String name = f['properties']['path'] ?? f['properties']['name'] ?? "";
              existingData[name] = f;
            }
          }
        }
      } catch (e) {
        debugPrint("Error reading existing GeoJSON: $e");
      }
    }

    Set<String> validClasses = {'Unclassified'};
    if (await classFile.exists()) {
      try {
        List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
        for (var item in jsonList) {
          validClasses.add(item['name']);
        }
      } catch (_) {}
    }

    List<FileSystemEntity> entities = await projectDir.list().toList();
    List<Map<String, dynamic>> features = [];

    for (var entity in entities) {
      if (entity is! File) continue;
      String fullPath = entity.path;
      String filename = p.basename(fullPath);

      if (!filename.toLowerCase().endsWith('.jpg') &&
          !filename.toLowerCase().endsWith('.png') &&
          !filename.toLowerCase().endsWith('.jpeg')) {
        continue;
      }

      Map<String, dynamic>? existingFeature = existingData[filename];

      String finalClass = "Unclassified";
      double lat = 0.0;
      double lng = 0.0;
      String time = entity.lastModifiedSync().toIso8601String();

      if (existingFeature != null) {
        var coords = existingFeature['geometry']['coordinates'];
        var props = existingFeature['properties'];

        if (coords != null && coords.length >= 2) {
          lng = (coords[0] as num).toDouble();
          lat = (coords[1] as num).toDouble();
        }
        if (props['class'] != null) finalClass = props['class'];
        if (props['time'] != null) time = props['time'];
      } else {
        if (projectType == 'classification') {
          List<String> parts = filename.split('_');
          if (parts.length >= 2) {
            String candidate = parts[1];
            if (validClasses.contains(candidate)) {
              finalClass = candidate;
            }
          }
        }

        final latLong = await MetadataExif.getLatLong(fullPath);
        if (latLong != null) {
          lat = latLong['lat']!;
          lng = latLong['lng']!;
        }
      }

      features.add({
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [lng, lat]
        },
        "properties": {
          "path": filename, // CRITICAL FIX: Changed from 'name' to 'path' to match saveToCsv!
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

  static Future<void> updateEntryAfterRename({
    required String projectName,
    required String oldName, // This is already a filename
    required String newName, // This is already a filename
    required String newPath, // We will ignore this and use newName
    required String newClass,
  }) async {
    final geoFile = await FileDirectories.getGeoJsonFile(projectName);
    if (!await geoFile.exists()) return;

    try {
      final Map<String, dynamic> geoJson = jsonDecode(await geoFile.readAsString());
      final List features = geoJson['features'];

      for (var feature in features) {
        // FIX: Safe lookup
        String savedName = feature['properties']['path'] ?? feature['properties']['name'] ?? "";
        if (savedName == oldName) {
          feature['properties']['path'] = newName;
          feature['properties']['class'] = newClass;
          feature['properties'].remove('name'); // Clean up old corruption
          break;
        }
      }

      await geoFile.writeAsString(jsonEncode(geoJson));
    } catch (e) {
      debugPrint("Error updating GeoJSON entry: $e");
    }
  }

  // --- 2. SAVE TO DATABASE (Saves Filename) ---
  static Future<void> saveToCsv({
    required String projectName,
    required String imagePath, // Still accept full path for logic
    required Position? position,
    String? className,
    String projectType = 'classification',
    DateTime? customTime,
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
      final String timestamp = (customTime ?? DateTime.now()).toLocal().toIso8601String();
      final String finalClass = (className ?? 'Unclassified').replaceAll(',', '');

      List<dynamic> features = geoData['features'];
      String filename = p.basename(imagePath);

      // Matches based on filename safely
      features.removeWhere((f) => (f['properties']['path'] ?? f['properties']['name'] ?? "") == filename);

      features.add({
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [lng, lat]
        },
        "properties": {
          "path": filename, // SAVING FILENAME ONLY
          "class": projectType == 'segmentation' ? "" : finalClass,
          "time": timestamp,
        }
      });

      await geoFile.writeAsString(jsonEncode(geoData));
    });
    await FileDirectories.saveLock;
  }

  // --- 3. READ DATA (Reconstructs Full Path for UI) ---
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

          // DYNAMIC RECONSTRUCTION:
          String filename = props['path'] ?? props['name'] ?? "";
          String currentValidPath = p.join(projectDir.path, filename);

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

        features.removeWhere((f) => (f['properties']['path'] ?? f['properties']['name'] ?? "") == filename);

        await geoFile.writeAsString(jsonEncode(geoJson));
      } catch (e) {
        debugPrint("Error removing entry: $e");
      }
    }
  }

  static Future<void> updateClassInCsv({
    required String projectName,
    required String imagePath,
    String? newImagePath, // This should be a filename or full path
    required String newClassName,
  }) async {
    final geoFile = await FileDirectories.getGeoJsonFile(projectName);
    String filename = p.basename(imagePath);

    if (await geoFile.exists()) {
      final Map<String, dynamic> geoJson = jsonDecode(await geoFile.readAsString());
      final List features = geoJson['features'];

      for (var f in features) {
        // FIX: Secure Lookup
        String savedName = f['properties']['path'] ?? f['properties']['name'] ?? "";
        if (savedName == filename) {
          f['properties']['class'] = newClassName;
          if (newImagePath != null) {
            f['properties']['path'] = p.basename(newImagePath);
            f['properties'].remove('name'); // Clean up old keys
          }
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
        // FIX: Secure Lookup
        if ((f['properties']['path'] ?? f['properties']['name'] ?? "") == filename) {
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