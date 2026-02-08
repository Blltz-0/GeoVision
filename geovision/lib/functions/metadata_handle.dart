import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';

class MetadataService {
  static Future<void> _saveLock = Future.value();

  /// Helper to get the central GeoJSON file reference
  static Future<File> _getGeoJsonFile(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/projects/$projectName/project_data.geojson');
  }

  // --- 1. REBUILD DATABASE (The "Nuclear" Sync - GeoJSON Version) ---
  static Future<void> rebuildProjectData(String projectName, {String projectType = 'classification'}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectName/images');
    final geoFile = await _getGeoJsonFile(projectName);
    final classFile = File('${appDir.path}/projects/$projectName/classes.json');

    if (!await projectDir.exists()) return;

    // 1. Load Valid Classes (The "Whitelist")
    Set<String> validClasses = {'Unclassified'};
    if (await classFile.exists()) {
      try {
        List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
        for (var item in jsonList) {
          validClasses.add(item['name']);
        }
      } catch (_) {}
    }

    // 2. Scan Files
    List<FileSystemEntity> entities = await projectDir.list().toList();
    List<Map<String, dynamic>> features = [];

    for (var entity in entities) {
      if (entity is! File) continue;
      String path = entity.path;
      String filename = path.split(Platform.pathSeparator).last;

      if (!filename.toLowerCase().endsWith('.jpg') && !filename.toLowerCase().endsWith('.png')) continue;

      String finalClass = "Unclassified";
      double lat = 0.0;
      double lng = 0.0;

      // 3. Extract and VALIDATE class from filename
      if (projectType == 'classification') {
        List<String> parts = filename.split('_');
        if (parts.length >= 2) {
          String candidate = parts[1];
          // Check if the filename-extracted class is actually in our classes.json
          if (validClasses.contains(candidate)) {
            finalClass = candidate;
          } else {
            debugPrint("⚠️ Validation: Class '$candidate' not found in project definitions. Resetting $filename to Unclassified.");
            finalClass = "Unclassified";
          }
        }
      }

      // 4. Extract EXIF
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

      features.add({
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [lng, lat]
        },
        "properties": {
          "path": path,
          "class": projectType == 'segmentation' ? "" : finalClass,
          "time": entity.lastModifiedSync().toIso8601String(),
        }
      });
    }

    final geoJson = {
      "type": "FeatureCollection",
      "features": features,
    };

    await geoFile.writeAsString(jsonEncode(geoJson));
    debugPrint("✅ GeoJSON Database Rebuilt and Validated for $projectName");
  }

  // --- 2. SAVE TO DATABASE (Append/Update GeoJSON) ---
  static Future<void> saveToCsv({
    required String projectName,
    required String imagePath,
    required Position? position,
    String? className,
    String projectType = 'classification',
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
      final String timestamp = DateTime.now().toIso8601String();
      final String finalClass = (className ?? 'Unclassified').replaceAll(',', '');

      (geoData['features'] as List).add({
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
    List<Map<String, dynamic>> dataPoints = [];

    if (await geoFile.exists()) {
      try {
        final Map<String, dynamic> geoJson = jsonDecode(await geoFile.readAsString());
        final List features = geoJson['features'] ?? [];

        for (var feature in features) {
          final props = feature['properties'] ?? {};
          final geometry = feature['geometry'] ?? {};
          final coords = geometry['coordinates'] ?? [0.0, 0.0];

          dataPoints.add({
            "path": props['path'] ?? "",
            "class": props['class'] ?? "Unclassified",
            "lat": (coords[1] as num).toDouble(), // Geographic Lat is index 1
            "lng": (coords[0] as num).toDouble(), // Geographic Lng is index 0
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
          return path.split(Platform.pathSeparator).last == filename;
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

    if (await geoFile.exists()) {
      final Map<String, dynamic> geoJson = jsonDecode(await geoFile.readAsString());
      final List features = geoJson['features'];

      for (var f in features) {
        if (f['properties']['path'] == imagePath) {
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

    if (await geoFile.exists()) {
      final Map<String, dynamic> geoJson = jsonDecode(await geoFile.readAsString());
      final List features = geoJson['features'];

      for (var f in features) {
        if (f['properties']['path'] == imagePath) {
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

  static Future<List<Map<String, dynamic>>> getClasses(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/projects/$projectName/classes.json');
    return (await file.exists()) ? List<Map<String, dynamic>>.from(jsonDecode(await file.readAsString())) : [];
  }

  static Future<void> deleteImage({required String projectName, required String imagePath, String projectType = 'classification'}) async {
    final File imageFile = File(imagePath);
    if (await imageFile.exists()) await imageFile.delete();

    final filename = imagePath.split(Platform.pathSeparator).last;
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
        .map((e) => e.path.split(Platform.pathSeparator).last)
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
      String currentFilename = oldImagePath.split(Platform.pathSeparator).last;

      if (currentFilename.startsWith("${cleanProject}_${cleanClass}_")) {
        await updateClassInCsv(projectName: projectName, imagePath: oldImagePath, newClassName: newClassName);
        await embedMetadata(filePath: oldImagePath, lat: 0, lng: 0, className: newClassName, updateClassOnly: true);
        return oldImagePath;
      }

      String newFileName = await generateNextFileName(projectDir, projectName, newClassName, projectType: projectType);
      String newImagePath = '${projectDir.path}/$newFileName';

      await oldFile.rename(newImagePath);
      await rebuildProjectData(projectName, projectType: projectType);
      await embedMetadata(filePath: newImagePath, lat: 0, lng: 0, className: newClassName, updateClassOnly: true);

      return newImagePath;
    } catch (e) {
      debugPrint("❌ Error tagging image: $e");
      return null;
    }
  }

  // --- LABEL MANAGEMENT ---
  static Future<File> _getLabelsFile(String projectName) async {
    final docDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${docDir.path}/projects/$projectName');
    if (!await projectDir.exists()) await projectDir.create(recursive: true);
    return File('${projectDir.path}/labels.json');
  }

  static Future<List<Map<String, dynamic>>> getLabels(String projectName) async {
    try {
      final file = await _getLabelsFile(projectName);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.isEmpty) return [];
      return List<Map<String, dynamic>>.from(jsonDecode(content));
    } catch (e) {
      debugPrint("Error reading labels: $e");
      return [];
    }
  }

  static Future<void> addLabelDefinition(String projectName, String name, int color) async {
    final labels = await getLabels(projectName);
    if (labels.any((l) => l['name'] == name)) return;
    labels.add({'name': name, 'color': color});
    await _saveLabelsToDisk(projectName, labels);
  }

  static Future<void> updateLabel(String projectName, String oldName, String newName, int newColor) async {
    final labels = await getLabels(projectName);
    final index = labels.indexWhere((l) => l['name'] == oldName);
    if (index != -1) {
      labels[index] = {'name': newName, 'color': newColor};
      await _saveLabelsToDisk(projectName, labels);
    }
  }

  static Future<void> deleteLabel(String projectName, String labelName) async {
    final labels = await getLabels(projectName);
    labels.removeWhere((l) => l['name'] == labelName);
    await _saveLabelsToDisk(projectName, labels);
  }

  static Future<void> _saveLabelsToDisk(String projectName, List<Map<String, dynamic>> labels) async {
    final file = await _getLabelsFile(projectName);
    await file.writeAsString(jsonEncode(labels));
  }
}