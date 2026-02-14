import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p; // Use path package for safe filename handling

class MetadataService {
  static Future<void> _saveLock = Future.value();

  /// Helper to get the central GeoJSON file reference
  static Future<File> _getGeoJsonFile(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/projects/$projectName/project_data.geojson');
  }

  // --- 1. REBUILD DATABASE (The "Smart" Sync - Preserves Data) ---
  static Future<void> rebuildProjectData(String projectName, {String projectType = 'classification'}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectName/images');
    final geoFile = await _getGeoJsonFile(projectName);
    final classFile = File('${appDir.path}/projects/$projectName/classes.json');

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

      if (!filename.toLowerCase().endsWith('.jpg') && !filename.toLowerCase().endsWith('.png') && !filename.toLowerCase().endsWith('.jpeg')) continue;

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
        try {
          final exif = await Exif.fromPath(path);
          final latLong = await exif.getLatLong();
          await exif.close();
          if (latLong != null) {
            lat = latLong.latitude;
            lng = latLong.longitude;
          }
        } catch (e) {
          debugPrint("⚠️ EXIF Read Error for $filename: $e");
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
    _saveLock = _saveLock.then((_) async {
      final geoFile = await _getGeoJsonFile(projectName);

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
    await _saveLock;
  }

  // --- 3. READ DATA ---
  static Future<List<Map<String, dynamic>>> readCsvData(String projectName) async {
    final geoFile = await _getGeoJsonFile(projectName);
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectName/images'); // Current valid path

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

  // --- 4. EMBED METADATA ---
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
        String formattedDate = "${time.year}:${time.month.toString().padLeft(2, '0')}:${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}";
        attributes['DateTimeOriginal'] = formattedDate;
        attributes['DateTimeDigitized'] = formattedDate;
      }

      await exif.writeAttributes(attributes);
      await exif.close();
    } catch (e) {
      debugPrint("⚠️ EXIF Error: $e");
    }
  }

  // --- 5. REMOVE SINGLE ENTRY ---
  static Future<void> removeEntry(String projectName, String filename) async {
    final geoFile = await _getGeoJsonFile(projectName);

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
    final geoFile = await _getGeoJsonFile(projectName);
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
    final geoFile = await _getGeoJsonFile(projectName);
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

    await embedMetadata(
      filePath: imagePath,
      lat: lat,
      lng: lng,
      time: time,
    );
  }

  // --- CLASS MANAGEMENT ---
  static Future<void> addClassDefinition(String projectName, String className, int colorValue) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/projects/$projectName/classes.json');
    List<dynamic> classes = (await file.exists()) ? jsonDecode(await file.readAsString()) : [];
    if (!classes.any((c) => c['name'] == className)) {
      classes.add({'name': className, 'color': colorValue});
      await file.writeAsString(jsonEncode(classes));
    }
  }

  static Future<void> addLabelDefinition(String projectName, String className, int colorValue) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/projects/$projectName/labels.json');
    List<dynamic> classes = (await file.exists()) ? jsonDecode(await file.readAsString()) : [];
    if (!classes.any((c) => c['name'] == className)) {
      classes.add({'name': className, 'color': colorValue});
      await file.writeAsString(jsonEncode(classes));
    }
  }

  static Future<List<Map<String, dynamic>>> getClasses(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/projects/$projectName/classes.json');
    return (await file.exists()) ? List<Map<String, dynamic>>.from(jsonDecode(await file.readAsString())) : [];
  }

  static Future<List<Map<String, dynamic>>> getLabels(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/projects/$projectName/labels.json');
    return (await file.exists()) ? List<Map<String, dynamic>>.from(jsonDecode(await file.readAsString())) : [];
  }

  static Future<void> deleteImage({required String projectName, required String imagePath, String projectType = 'classification'}) async {
    final File imageFile = File(imagePath);
    if (await imageFile.exists()) await imageFile.delete();

    final filename = p.basename(imagePath);
    await removeEntry(projectName, filename);
  }

  static Future<void> deleteClass(String projectName, String className) async {
    final directory = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${directory.path}/projects/$projectName');
    final classFile = File('${projectDir.path}/classes.json');

    if (await classFile.exists()) {
      List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
      jsonList.removeWhere((c) => c['name'] == className);
      await classFile.writeAsString(jsonEncode(jsonList));
    }
    await _bulkUpdateCsvClass(projectName, className, "Unclassified");
  }

  static Future<void> deleteLabel(String projectName, String className) async {
    final directory = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${directory.path}/projects/$projectName');
    final classFile = File('${projectDir.path}/labels.json');

    if (await classFile.exists()) {
      List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
      jsonList.removeWhere((c) => c['name'] == className);
      await classFile.writeAsString(jsonEncode(jsonList));
    }
    await _bulkUpdateCsvClass(projectName, className, "Unclassified");
  }

  static Future<void> updateClass(String projectName, String oldName, String newName, int newColor) async {
    final directory = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${directory.path}/projects/$projectName');
    final classFile = File('${projectDir.path}/classes.json');

    if (await classFile.exists()) {
      List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
      for (var c in jsonList) {
        if (c['name'] == oldName) {
          c['name'] = newName;
          c['color'] = newColor;
        }
      }
      await classFile.writeAsString(jsonEncode(jsonList));
    }
    if (oldName != newName) {
      await _bulkUpdateCsvClass(projectName, oldName, newName);
    }
  }

  static Future<void> updateLabel(String projectName, String oldName, String newName, int newColor) async {
    final directory = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${directory.path}/projects/$projectName');
    final classFile = File('${projectDir.path}/labels.json');

    if (await classFile.exists()) {
      List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
      for (var c in jsonList) {
        if (c['name'] == oldName) {
          c['name'] = newName;
          c['color'] = newColor;
        }
      }
      await classFile.writeAsString(jsonEncode(jsonList));
    }
    if (oldName != newName) {
      await _bulkUpdateCsvClass(projectName, oldName, newName);
    }
  }

  static Future<void> _bulkUpdateCsvClass(String projectName, String targetClass, String newClassValue) async {
    final geoFile = await _getGeoJsonFile(projectName);
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

  static Future<int> getLatestIndex(
      Directory projectDir,
      String projectName,
      String className,
      {String projectType = 'classification'}
      ) async {

    if (!await projectDir.exists()) return 0;

    // 1. Clean strings to match your naming convention
    String cleanProject = projectName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    String cleanClass = className.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    if (cleanClass.isEmpty && projectType == 'classification') cleanClass = "Unclassified";

    // 2. Define the prefix we are looking for
    String prefix = projectType == 'segmentation'
        ? "${cleanProject}_"
        : "${cleanProject}_${cleanClass}_";

    int maxCount = 0;

    // 3. Stream files (Memory efficient)
    try {
      await for (var entity in projectDir.list(followLinks: false)) {
        if (entity is File) {
          String name = p.basename(entity.path);

          if (name.startsWith(prefix)) {
            try {
              // Remove prefix
              String temp = name.substring(prefix.length);
              // Remove extension
              int dotIndex = temp.lastIndexOf('.');
              if (dotIndex != -1) {
                String numberPart = temp.substring(0, dotIndex);
                int? val = int.tryParse(numberPart);
                if (val != null && val > maxCount) {
                  maxCount = val;
                }
              }
            } catch (e) {
              // Ignore malformed files
            }
          }
        }
      }
    } catch (e) {
      print("Error scanning directory index: $e");
    }

    return maxCount;
  }

  // --- FILE RENAMING / TAGGING ---
  static Future<String> generateNextFileName(
      Directory projectDir,
      String projectName,
      String className,
      {String projectType = 'classification', Set<String>? existingNames}
      ) async {
    String cleanProject = projectName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    String cleanClass = className.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    if (cleanClass.isEmpty && projectType == 'classification') cleanClass = "Unclassified";

    Set<String> names = existingNames ?? (await projectDir.list().toList())
        .whereType<File>()
        .map((e) => p.basename(e.path))
        .toSet();

    int counter = 1;
    while (true) {
      String fileName = projectType == 'segmentation'
          ? "${cleanProject}_$counter.jpg"
          : "${cleanProject}_${cleanClass}_$counter.jpg";

      if (!names.contains(fileName)) {
        return fileName;
      }
      counter++;
    }
  }

  static Future<String?> tagImage(String projectName, String oldImagePath, String newClassName, {String projectType = 'classification'}) async {
    if (projectType == 'segmentation') return oldImagePath;

    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectName/images');
    final File oldFile = File(oldImagePath);
    if (!await oldFile.exists()) return null;

    try {
      String cleanProject = projectName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      String cleanClass = newClassName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      String currentFilename = p.basename(oldImagePath);

      if (currentFilename.startsWith("${cleanProject}_${cleanClass}_")) {
        // Just update metadata
        await updateClassInCsv(projectName: projectName, imagePath: oldImagePath, newClassName: newClassName);
        await embedMetadata(filePath: oldImagePath, lat: 0, lng: 0, className: newClassName, updateClassOnly: true);
        return oldImagePath;
      }

      String newFileName = await generateNextFileName(projectDir, projectName, newClassName, projectType: projectType);
      String newImagePath = '${projectDir.path}/$newFileName';

      await oldFile.rename(newImagePath);

      // We must save the new entry to GeoJSON manually or rebuild.
      // Rebuild is safer to keep things in sync.
      await rebuildProjectData(projectName, projectType: projectType);

      // Re-embed metadata on new file
      await embedMetadata(filePath: newImagePath, lat: 0, lng: 0, className: newClassName, updateClassOnly: true);

      return newImagePath;
    } catch (e) {
      debugPrint("❌ Error tagging image: $e");
      return null;
    }
  }
}