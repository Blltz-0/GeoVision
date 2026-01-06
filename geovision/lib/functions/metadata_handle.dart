import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';

class MetadataService {
  static Future<void> _saveLock = Future.value();

  // --- 1. REBUILD DATABASE (The "Nuclear" Sync) ---
  // This function scans the disk, reads EXIF from every image,
  // and completely rewrites the CSV.
  static Future<void> rebuildProjectData(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectName/images');
    final csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');
    final classFile = File('${appDir.path}/projects/$projectName/classes.json');

    if (!await projectDir.exists()) return;

    // 1. Load Valid Classes
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
    List<String> newCsvRows = [];

    // Header
    newCsvRows.add('path,class,lat,lng,time');

    for (var entity in entities) {
      if (entity is! File) continue;
      String path = entity.path;
      String filename = path.split(Platform.pathSeparator).last;

      // Filter for images only
      if (!filename.toLowerCase().endsWith('.jpg') &&
          !filename.toLowerCase().endsWith('.png')) {
        continue;
      }

      String finalClass = "Unclassified";
      double lat = 0.0;
      double lng = 0.0;

      // 3. Extract Data from Filename (Priority 1)
      // Format: ProjectName_ClassName_Number.jpg
      List<String> parts = filename.split('_');
      if (parts.length >= 2) {
        String candidate = parts[1];
        if (validClasses.contains(candidate)) {
          finalClass = candidate;
        } else if (int.tryParse(candidate) == null) {
          // If it's not a number and not in the list, it might be a class we forgot
          // But for strictness, you can default to Unclassified
          finalClass = "Unclassified";
        }
      }

      // 4. Extract Data from EXIF (Priority 2 - Overwrites if found)
      try {
        final exif = await Exif.fromPath(path);
        final latLong = await exif.getLatLong();
        await exif.close();

        if (latLong != null) {
          lat = latLong.latitude;
          lng = latLong.longitude;
        }
        // Optional: If you trust EXIF class more than filename, uncomment this:
        // if (userComment != null && validClasses.contains(userComment.toString())) {
        //   finalClass = userComment.toString();
        // }
      } catch (e) {
        debugPrint("⚠️ EXIF Read Error for $filename: $e");
      }

      // 5. Add to List
      // We store just the filename for portability, or full path if you prefer.
      // Using full path as per your original code style.
      String time = entity.lastModifiedSync().toIso8601String();
      newCsvRows.add('$path,$finalClass,$lat,$lng,$time');
    }

    // 6. Write to CSV
    await csvFile.writeAsString('${newCsvRows.join('\n')}\n');
    debugPrint("✅ Project Database Rebuilt for $projectName");
  }

  // --- EXISTING METHODS (Kept the same) ---

  static Future<void> saveToCsv({
    required String projectName,
    required String imagePath,
    required Position? position,
    String? className,
  }) async {
    _saveLock = _saveLock.then((_) async {
      final appDir = await getApplicationDocumentsDirectory();
      final File csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');

      // Ensure directory exists
      if (!await csvFile.parent.exists()) {
        await csvFile.parent.create(recursive: true);
      }

      final String cleanPath = imagePath.replaceAll(',', '');
      final String cls = (className ?? 'Unclassified').replaceAll(',', '');
      final String lat = position?.latitude.toString() ?? '0.0';
      final String lng = position?.longitude.toString() ?? '0.0';
      final String timestamp = DateTime.now().toIso8601String();

      final bool fileAlreadyExists = await csvFile.exists();
      final bool fileHasContent = fileAlreadyExists && await csvFile.length() > 0;

      final IOSink sink = csvFile.openWrite(mode: FileMode.append);
      try {
        if (!fileHasContent) {
          sink.writeln('path,class,lat,lng,time');
        }
        sink.writeln([cleanPath, cls, lat, lng, timestamp].join(','));
      } finally {
        await sink.flush();
        await sink.close();
      }
    });
    await _saveLock;
  }

  static Future<List<Map<String, dynamic>>> readCsvData(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final File csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');

    List<Map<String, dynamic>> dataPoints = [];

    if (await csvFile.exists()) {
      List<String> lines = await csvFile.readAsLines();

      for (String line in lines) {
        if (line.trim().isEmpty || line.startsWith("path")) continue;
        List<String> parts = line.split(',');
        if (parts.length >= 4) {
          dataPoints.add({
            "path": parts[0],
            "class": parts.length > 1 ? parts[1] : "Unclassified",
            "lat": parts.length > 2 ? (double.tryParse(parts[2]) ?? 0.0) : 0.0,
            "lng": parts.length > 3 ? (double.tryParse(parts[3]) ?? 0.0) : 0.0,
            "time": parts.length > 4 ? parts[4] : "",
          });
        }
      }
    }
    return dataPoints;
  }

  // Helper helpers (restore from your code)
  static Future<void> embedMetadata({required String filePath, required double lat, required double lng, String? className}) async {
    try {
      final exif = await Exif.fromPath(filePath);
      Map<String, Object> attributes = {
        'GPSLatitude': lat.abs(),
        'GPSLatitudeRef': lat >= 0 ? 'N' : 'S',
        'GPSLongitude': lng.abs(),
        'GPSLongitudeRef': lng >= 0 ? 'E' : 'W',
      };
      if (className != null) attributes['UserComment'] = className;
      await exif.writeAttributes(attributes);
      await exif.close();
    } catch (e) {
      debugPrint("⚠️ EXIF Error: $e");
    }
  }

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

  static Future<void> deleteImage({required String projectName, required String imagePath}) async {
    final File imageFile = File(imagePath);
    if (await imageFile.exists()) await imageFile.delete();
    // Simple rebuild to clean CSV
    await rebuildProjectData(projectName);
  }

  // 1. DELETE CLASS & RECLASSIFY IMAGES
  static Future<void> deleteClass(String projectName, String className) async {
    final directory = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${directory.path}/projects/$projectName');
    final classFile = File('${projectDir.path}/classes.json');

    // A. Remove from classes.json
    if (await classFile.exists()) {
      String content = await classFile.readAsString();
      List<dynamic> jsonList = jsonDecode(content);

      // Remove the class
      jsonList.removeWhere((c) => c['name'] == className);

      await classFile.writeAsString(jsonEncode(jsonList));
    }

    // B. Reclassify images in CSV to "Unclassified"
    await _bulkUpdateCsvClass(projectName, className, "Unclassified");
  }

  // 2. UPDATE CLASS NAME/COLOR
  static Future<void> updateClass(String projectName, String oldName, String newName, int newColor) async {
    final directory = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${directory.path}/projects/$projectName');
    final classFile = File('${projectDir.path}/classes.json');

    // A. Update classes.json
    if (await classFile.exists()) {
      String content = await classFile.readAsString();
      List<dynamic> jsonList = jsonDecode(content);

      for (var c in jsonList) {
        if (c['name'] == oldName) {
          c['name'] = newName;
          c['color'] = newColor;
        }
      }
      await classFile.writeAsString(jsonEncode(jsonList));
    }

    // B. If name changed, update all CSV records
    if (oldName != newName) {
      await _bulkUpdateCsvClass(projectName, oldName, newName);
    }
  }

  // --- HELPER: BULK UPDATE CSV ---
  static Future<void> _bulkUpdateCsvClass(String projectName, String targetClass, String newClassValue) async {
    // 1. Read existing data
    List<Map<String, dynamic>> rows = await readCsvData(projectName);
    bool changed = false;

    // 2. Modify rows
    for (var row in rows) {
      if (row['class'] == targetClass) {
        row['class'] = newClassValue;
        changed = true;
      }
    }

    // 3. Save back to disk if changes happened
    if (changed) {
      // We reuse your save logic. Since readCsvData parses the CSV,
      // we simply need to write it back in the standard format.
      final directory = await getApplicationDocumentsDirectory();
      final File csvFile = File('${directory.path}/projects/$projectName/project_data.csv');
      final IOSink sink = csvFile.openWrite();

      sink.writeln("path,class,lat,lng,time"); // Header

      for (var row in rows) {
        String path = row['path'];
        String cls = row['class'] ?? 'Unclassified';
        String lat = row['lat'].toString();
        String lng = row['lng'].toString();
        String time = row['time'].toString();

        // Helper to extract filename if your CSV stores full paths differently
        String filename = path.split(Platform.pathSeparator).last;

        // Ensure we write consistent data
        sink.writeln("$filename,$cls,$lat,$lng,$time");
      }
      await sink.flush();
      await sink.close();
    }
  }

  // 1. STRICT FILE NAME GENERATOR
  // This forces the format: ProjectName_ClassName_1.jpg
  // It effectively "cleans" the file of any old names like "Unclassified"
  static Future<String> generateNextFileName(Directory projectDir, String projectName, String className) async {
    // Sanitize: Remove symbols, replace spaces with underscores
    String cleanProject = projectName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    String cleanClass = className.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');

    if (cleanClass.isEmpty) cleanClass = "Unclassified";

    int counter = 1;
    while (true) {
      // STRICT FORMAT: Project_Class_Number.jpg
      String fileName = "${cleanProject}_${cleanClass}_$counter.jpg";

      // If this specific number doesn't exist, we use it.
      if (!await File('${projectDir.path}/$fileName').exists()) {
        return fileName;
      }
      counter++;
    }
  }

  // 2. TAG IMAGE (Uses the generator above)
  static Future<String?> tagImage(String projectName, String oldImagePath, String newClassName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectName/images');

    final File oldFile = File(oldImagePath);
    if (!await oldFile.exists()) return null;

    try {
      // PREVENT "NUMBER JUMPING"
      // Check if the file is ALREADY correctly named.
      // e.g. If renaming "Project_Tree_1.jpg" to "Tree", don't change it to "Project_Tree_2.jpg"

      String cleanProject = projectName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      String cleanClass = newClassName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      String currentFilename = oldImagePath.split(Platform.pathSeparator).last;

      // If the filename already starts with "Project_Class_", just save metadata and stop.
      if (currentFilename.startsWith("${cleanProject}_${cleanClass}_")) {
        debugPrint("File is already named correctly. Updating metadata only.");
        // Still update internal metadata just in case
        final exif = await Exif.fromPath(oldImagePath);
        final latLong = await exif.getLatLong();
        await exif.close();

        await embedMetadata(
            filePath: oldImagePath,
            lat: latLong?.latitude ?? 0.0,
            lng: latLong?.longitude ?? 0.0,
            className: newClassName
        );
        await rebuildProjectData(projectName);
        return oldImagePath;
      }

      // GENERATE NEW NAME (Clean Slate)
      String newFileName = await generateNextFileName(projectDir, projectName, newClassName);
      String newImagePath = '${projectDir.path}/$newFileName';

      // RENAME
      await oldFile.rename(newImagePath);

      // UPDATE METADATA
      final exif = await Exif.fromPath(newImagePath);
      final latLong = await exif.getLatLong();
      await exif.close();

      await embedMetadata(
          filePath: newImagePath,
          lat: latLong?.latitude ?? 0.0,
          lng: latLong?.longitude ?? 0.0,
          className: newClassName
      );

      // SYNC DATABASE
      await rebuildProjectData(projectName);

      return newImagePath;

    } catch (e) {
      debugPrint("❌ Error tagging image: $e");
      return null;
    }
  }

  // Helper to overwrite CSV (if you don't have one exposed yet)
  static Future<void> _writeCsvOver(String projectName, List<Map<String, dynamic>> data) async {
    final docDir = await getApplicationDocumentsDirectory();
    final file = File('${docDir.path}/projects/$projectName/project_data.csv');
    final sink = file.openWrite();

    // Header
    sink.writeln("path,class,lat,lng,time");

    // Rows
    for (var row in data) {
      // Ensure we don't write nulls
      final p = row['path'] ?? '';
      final c = row['class'] ?? 'Unclassified';
      final lat = row['lat'] ?? 0.0;
      final lng = row['lng'] ?? 0.0;
      final t = row['time'] ?? '';

      // Extract filename from path for the first column if your CSV format expects filename,
      // otherwise use full path depending on your specific CSV structure.
      // Based on previous code, you stored filename in first col usually,
      // but let's assume standard format:
      final filename = p.split(Platform.pathSeparator).last;

      sink.writeln("$filename,$c,$lat,$lng,$t");
    }
    await sink.flush();
    await sink.close();
  }

  static Future<File> _getLabelsFile(String projectName) async {
    final docDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${docDir.path}/projects/$projectName');
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }
    return File('${projectDir.path}/labels.json');
  }

  /// 1. GET ALL LABELS
  static Future<List<Map<String, dynamic>>> getLabels(String projectName) async {
    try {
      final file = await _getLabelsFile(projectName);
      if (!await file.exists()) {
        // Return empty list if file doesn't exist yet
        return [];
      }
      final content = await file.readAsString();
      if (content.isEmpty) return [];

      final List<dynamic> jsonList = jsonDecode(content);
      return List<Map<String, dynamic>>.from(jsonList);
    } catch (e) {
      debugPrint("Error reading labels: $e");
      return [];
    }
  }

  /// 2. ADD NEW LABEL
  static Future<void> addLabelDefinition(String projectName, String name, int color) async {
    final labels = await getLabels(projectName);

    // Prevent duplicates based on name
    if (labels.any((l) => l['name'] == name)) return;

    labels.add({
      'name': name,
      'color': color,
    });

    await _saveLabelsToDisk(projectName, labels);
  }

  /// 3. UPDATE EXISTING LABEL
  static Future<void> updateLabel(String projectName, String oldName, String newName, int newColor) async {
    final labels = await getLabels(projectName);
    final index = labels.indexWhere((l) => l['name'] == oldName);

    if (index != -1) {
      labels[index] = {
        'name': newName,
        'color': newColor,
      };
      await _saveLabelsToDisk(projectName, labels);

      // Note: If you store applied labels in your CSV (e.g. in a "tags" column),
      // you would ideally iterate through the CSV here and rename the tag there too.
    }
  }

  /// 4. DELETE LABEL
  static Future<void> deleteLabel(String projectName, String labelName) async {
    final labels = await getLabels(projectName);

    // Remove the definition
    labels.removeWhere((l) => l['name'] == labelName);

    await _saveLabelsToDisk(projectName, labels);

    // Note: To be fully consistent, you might want to open project_data.csv
    // and remove this label from any image that has it applied.
  }

  /// Helper to write the list back to disk
  static Future<void> _saveLabelsToDisk(String projectName, List<Map<String, dynamic>> labels) async {
    final file = await _getLabelsFile(projectName);
    await file.writeAsString(jsonEncode(labels));
  }


}