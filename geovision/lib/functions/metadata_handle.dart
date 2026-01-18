import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';

class MetadataService {
  static Future<void> _saveLock = Future.value();

  // --- 1. REBUILD DATABASE (The "Nuclear" Sync) ---
  static Future<void> rebuildProjectData(String projectName, {String projectType = 'classification'}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectName/images');
    final csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');
    final classFile = File('${appDir.path}/projects/$projectName/classes.json');

    if (!await projectDir.exists()) return;

    // 1. Load Valid Classes (Only for classification)
    Set<String> validClasses = {'Unclassified'};
    if (projectType == 'classification' && await classFile.exists()) {
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

      if (!filename.toLowerCase().endsWith('.jpg') &&
          !filename.toLowerCase().endsWith('.png')) {
        continue;
      }

      String finalClass = "";

      if (projectType == 'classification') {
        finalClass = "Unclassified";
      }

      double lat = 0.0;
      double lng = 0.0;

      // 3. Extract Data from Filename (Classification only)
      if (projectType == 'classification') {
        List<String> parts = filename.split('_');
        if (parts.length >= 2) {
          String candidate = parts[1];
          if (validClasses.contains(candidate)) {
            finalClass = candidate;
          } else if (int.tryParse(candidate) == null) {
            finalClass = "Unclassified";
          }
        }
      }

      // 4. Extract Data from EXIF
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

      // 5. Add to List
      String time = entity.lastModifiedSync().toIso8601String();
      newCsvRows.add('$path,$finalClass,$lat,$lng,$time');
    }

    // 6. Write to CSV
    await csvFile.writeAsString('${newCsvRows.join('\n')}\n');
    debugPrint("✅ Project Database Rebuilt for $projectName ($projectType)");
  }

  // --- 2. SAVE TO CSV (Append) ---
  static Future<void> saveToCsv({
    required String projectName,
    required String imagePath,
    required Position? position,
    String? className,
    String projectType = 'classification',
  }) async {
    _saveLock = _saveLock.then((_) async {
      final appDir = await getApplicationDocumentsDirectory();
      final File csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');

      if (!await csvFile.parent.exists()) {
        await csvFile.parent.create(recursive: true);
      }

      final String cleanPath = imagePath.replaceAll(',', '');

      String cls = '';
      if (projectType == 'classification') {
        cls = (className ?? 'Unclassified').replaceAll(',', '');
      }

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

  // --- 3. READ CSV DATA ---
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
            "class": parts.length > 1 ? parts[1] : "",
            "lat": parts.length > 2 ? (double.tryParse(parts[2]) ?? 0.0) : 0.0,
            "lng": parts.length > 3 ? (double.tryParse(parts[3]) ?? 0.0) : 0.0,
            "time": parts.length > 4 ? parts[4] : "",
          });
        }
      }
    }
    return dataPoints;
  }

  // --- 4. EMBED METADATA (Updated for Bulk Tagging) ---
  static Future<void> embedMetadata({
    required String filePath,
    required double lat,
    required double lng,
    String? className,
    DateTime? time,
    bool updateClassOnly = false, // ADDED: Flag to preserve existing LatLng
  }) async {
    try {
      final exif = await Exif.fromPath(filePath);
      Map<String, Object> attributes = {};

      // If we are NOT only updating the class, we write lat/lng
      if (!updateClassOnly) {
        attributes['GPSLatitude'] = lat.abs();
        attributes['GPSLatitudeRef'] = lat >= 0 ? 'N' : 'S';
        attributes['GPSLongitude'] = lng.abs();
        attributes['GPSLongitudeRef'] = lng >= 0 ? 'E' : 'W';
      }

      // Update UserComment (Class)
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

  // --- NEW METHOD: REMOVE SINGLE ENTRY FROM CSV ---
  static Future<void> removeEntry(String projectName, String filename) async {
    final appDir = await getApplicationDocumentsDirectory();
    final File csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');

    if (await csvFile.exists()) {
      List<String> lines = await csvFile.readAsLines();
      List<String> newLines = [];

      // Keep Header
      if (lines.isNotEmpty) newLines.add(lines[0]);

      for (int i = 1; i < lines.length; i++) {
        // Only keep lines that DO NOT end with the filename
        if (!lines[i].contains(filename)) {
          newLines.add(lines[i]);
        }
      }

      await csvFile.writeAsString(newLines.join('\n'));
    }
  }

  // --- NEW METHOD: UPDATE SINGLE CLASS IN CSV ---
  static Future<void> updateClassInCsv({
    required String projectName,
    required String imagePath,
    required String newClassName,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final File csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');
    final String targetFilename = imagePath.split(Platform.pathSeparator).last;

    if (await csvFile.exists()) {
      List<String> lines = await csvFile.readAsLines();
      List<String> newLines = [];

      if (lines.isNotEmpty) newLines.add(lines[0]); // Header

      for (int i = 1; i < lines.length; i++) {
        String line = lines[i];
        List<String> parts = line.split(',');

        // Identify row by filename (safest bet)
        if (parts.isNotEmpty && parts[0].endsWith(targetFilename)) {
          // Reconstruct the line with the new class
          String path = parts[0];
          // parts[1] is class, skip it
          String lat = parts.length > 2 ? parts[2] : "0.0";
          String lng = parts.length > 3 ? parts[3] : "0.0";
          String time = parts.length > 4 ? parts[4] : "";

          newLines.add("$path,$newClassName,$lat,$lng,$time");
        } else {
          newLines.add(line);
        }
      }

      await csvFile.writeAsString(newLines.join('\n'));
    }
  }

  // --- 5. UPDATE IMAGE METADATA ---
  static Future<void> updateImageMetadata({
    required String projectName,
    required String imagePath,
    required double lat,
    required double lng,
    required DateTime time,
    String projectType = 'classification',
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final File csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');

    // A. Update CSV
    if (await csvFile.exists()) {
      List<String> lines = await csvFile.readAsLines();
      List<String> newLines = [];
      if (lines.isNotEmpty) newLines.add(lines[0]); // Keep Header

      String targetName = imagePath.split(Platform.pathSeparator).last;
      bool found = false;

      for (int i = 1; i < lines.length; i++) {
        String line = lines[i];
        List<String> parts = line.split(',');

        if (parts.isNotEmpty && parts[0].endsWith(targetName)) {
          String currentPath = parts[0];
          String currentClass = parts.length > 1 ? parts[1] : (projectType == 'classification' ? "Unclassified" : "");

          String newLine = "$currentPath,$currentClass,$lat,$lng,${time.toIso8601String()}";
          newLines.add(newLine);
          found = true;
        } else {
          newLines.add(line);
        }
      }

      if (found) {
        await csvFile.writeAsString(newLines.join('\n'));
      }
    }

    // B. Update EXIF on the actual file
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

    // Instead of full rebuild, we can just remove the entry now
    final filename = imagePath.split(Platform.pathSeparator).last;
    await removeEntry(projectName, filename);
  }

  static Future<void> deleteClass(String projectName, String className) async {
    final directory = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${directory.path}/projects/$projectName');
    final classFile = File('${projectDir.path}/classes.json');

    if (await classFile.exists()) {
      String content = await classFile.readAsString();
      List<dynamic> jsonList = jsonDecode(content);
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
    if (oldName != newName) {
      await _bulkUpdateCsvClass(projectName, oldName, newName);
    }
  }

  static Future<void> _bulkUpdateCsvClass(String projectName, String targetClass, String newClassValue) async {
    List<Map<String, dynamic>> rows = await readCsvData(projectName);
    bool changed = false;

    for (var row in rows) {
      if (row['class'] == targetClass) {
        row['class'] = newClassValue;
        changed = true;
      }
    }

    if (changed) {
      final directory = await getApplicationDocumentsDirectory();
      final File csvFile = File('${directory.path}/projects/$projectName/project_data.csv');
      final IOSink sink = csvFile.openWrite();
      sink.writeln("path,class,lat,lng,time");

      for (var row in rows) {
        String path = row['path'];
        String cls = row['class'] ?? 'Unclassified';
        String lat = row['lat'].toString();
        String lng = row['lng'].toString();
        String time = row['time'].toString();
        // Ensure standard formatting
        String filename = path.split(Platform.pathSeparator).last;
        // Reconstruct full path if necessary, or just use what was in CSV
        // Here we assume the CSV path is sufficient.
        sink.writeln("$path,$cls,$lat,$lng,$time");
      }
      await sink.flush();
      await sink.close();
    }
  }

  // --- FILE RENAMING / TAGGING ---

  static Future<String> generateNextFileName(Directory projectDir, String projectName, String className, {String projectType = 'classification'}) async {
    String cleanProject = projectName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    String cleanClass = className.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');

    if (cleanClass.isEmpty && projectType == 'classification') cleanClass = "Unclassified";

    int counter = 1;
    while (true) {
      String fileName;

      if (projectType == 'segmentation') {
        fileName = "${cleanProject}_$counter.jpg";
      } else {
        fileName = "${cleanProject}_${cleanClass}_$counter.jpg";
      }

      if (!await File('${projectDir.path}/$fileName').exists()) {
        return fileName;
      }
      counter++;
    }
  }

  static Future<String?> tagImage(String projectName, String oldImagePath, String newClassName, {String projectType = 'classification'}) async {
    if (projectType == 'segmentation') {
      debugPrint("Tagging skipped for Segmentation project");
      return oldImagePath;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectName/images');

    final File oldFile = File(oldImagePath);
    if (!await oldFile.exists()) return null;

    try {
      String cleanProject = projectName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      String cleanClass = newClassName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      String currentFilename = oldImagePath.split(Platform.pathSeparator).last;

      if (currentFilename.startsWith("${cleanProject}_${cleanClass}_")) {
        debugPrint("File is already named correctly. Updating metadata only.");

        // Use updateClassInCsv for efficiency
        await updateClassInCsv(projectName: projectName, imagePath: oldImagePath, newClassName: newClassName);

        // Update EXIF
        await embedMetadata(
            filePath: oldImagePath,
            lat: 0, // Ignored
            lng: 0,
            className: newClassName,
            updateClassOnly: true // Preserve LatLng
        );
        return oldImagePath;
      }

      String newFileName = await generateNextFileName(projectDir, projectName, newClassName, projectType: projectType);
      String newImagePath = '${projectDir.path}/$newFileName';

      await oldFile.rename(newImagePath);

      // We moved the file, so we need to rebuild or update the CSV entry extensively.
      // For simplicity/safety on rename, we can rebuild.
      // Or we could implement a "moveEntry" method, but rebuildProjectData is safer for file renames.
      await rebuildProjectData(projectName, projectType: projectType);

      // Re-embed metadata in new file
      await embedMetadata(
          filePath: newImagePath,
          lat: 0,
          lng: 0,
          className: newClassName,
          updateClassOnly: true
      );

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
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }
    return File('${projectDir.path}/labels.json');
  }

  static Future<List<Map<String, dynamic>>> getLabels(String projectName) async {
    try {
      final file = await _getLabelsFile(projectName);
      if (!await file.exists()) {
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

  static Future<void> addLabelDefinition(String projectName, String name, int color) async {
    final labels = await getLabels(projectName);
    if (labels.any((l) => l['name'] == name)) return;

    labels.add({
      'name': name,
      'color': color,
    });
    await _saveLabelsToDisk(projectName, labels);
  }

  static Future<void> updateLabel(String projectName, String oldName, String newName, int newColor) async {
    final labels = await getLabels(projectName);
    final index = labels.indexWhere((l) => l['name'] == oldName);

    if (index != -1) {
      labels[index] = {
        'name': newName,
        'color': newColor,
      };
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