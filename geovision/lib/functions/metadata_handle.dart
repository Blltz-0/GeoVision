import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';

class MetadataService {
  static Future<void> _saveLock = Future.value();

  // ----------------------------------------------------------------
  // 1. APPEND: Save a new photo's data to the CSV
  // ----------------------------------------------------------------
  static Future<void> saveToCsv({
    required String projectName,
    required String imagePath,
    required Position? position,
    String? className,
  }) async {
    _saveLock = _saveLock.then((_) async {
      final appDir = await getApplicationDocumentsDirectory();
      final File csvFile = File(
          '${appDir.path}/projects/$projectName/project_data.csv');

      // Prepare Data
      // Remove commas from path to prevent breaking the CSV columns
      String cleanPath = imagePath.replaceAll(',', '');
      String lat = position?.latitude.toString() ?? "0.0";
      String lng = position?.longitude.toString() ?? "0.0";
      String time = DateTime.now().toIso8601String();
      String cls = className ?? "Unclassified";

      if (await csvFile.exists() && await csvFile.length() > 0) {
      }

      // Format: path,latitude,longitude,timestamp
      String newRow = "$cleanPath,$lat,$lng,$time,$cls\n";


      try {
        // Write Header if file is new

        if (!await csvFile.exists() || await csvFile.length() == 0) {
          await csvFile.writeAsString(
              "image_path,lat,lng,time,class\n"); // Added 'class' column
        }

        // Append the new row
        await csvFile.writeAsString(newRow, mode: FileMode.append);
      } catch (e) {
        if (kDebugMode) {
          print("❌ Error saving CSV: $e");
        }
      }
    });
    await _saveLock;
  }

  static Future<void> tagImage(String projectName, String oldImagePath, String newClassName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectName/images');
    final csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');

    final File oldFile = File(oldImagePath);
    if (!await oldFile.exists()) return;

    try {
      // 1. GENERATE NEW PATH
      // Find the next available number for the NEW class
      String newFileName = await generateNextFileName(projectDir, projectName, newClassName);
      String newImagePath = '${projectDir.path}/$newFileName';

      // 2. RENAME FILE
      // File.rename moves the file to the new name/path
      await oldFile.rename(newImagePath);
      print("📂 Renamed file to: $newFileName");

      // 3. UPDATE EXIF (Inject new Class Name)
      // We pass 0.0 for lat/lng here just to satisfy arguments,
      // BUT strictly we should read old GPS, update tag, write back.
      // For simplicity, let's assume we just want to update the UserComment tag.
      // (Using native_exif to update just one tag is tricky,
      // usually easier to re-write all attributes if you have them stored).

      // Let's do a quick read-update-write cycle for EXIF to be safe:
      final exif = await Exif.fromPath(newImagePath);
      final latLong = await exif.getLatLong(); // Preserve GPS
      final double lat = latLong?.latitude ?? 0.0;
      final double lng = latLong?.longitude ?? 0.0;
      await exif.close();

      // Write back with new Class Name
      await embedMetadata(
          filePath: newImagePath,
          lat: lat,
          lng: lng,
          className: newClassName
      );

      // 4. UPDATE CSV (Path AND Class)
      if (await csvFile.exists()) {
        List<String> lines = await csvFile.readAsLines();
        List<String> updatedLines = [];

        for (String line in lines) {
          if (line.trim().isEmpty) continue;

          // Check if this line belongs to the OLD image path
          // We check 'contains' carefully or split first to be precise
          if (line.contains(oldImagePath)) {
            List<String> parts = line.split(',');
            if (parts.length >= 4) {
              // Reconstruct: NewPath, Lat, Lng, Time, NewClass
              // We keep the old Lat/Lng/Time from the CSV text
              String baseLat = parts[1];
              String baseLng = parts[2];
              String baseTime = parts[3];

              // Warning: CSV Paths might contain commas? Assuming no for now.
              String cleanNewPath = newImagePath.replaceAll(',', '');

              updatedLines.add("$cleanNewPath,$baseLat,$baseLng,$baseTime,$newClassName");
            }
          } else {
            updatedLines.add(line);
          }
        }
        await csvFile.writeAsString(updatedLines.join('\n'));
      }

    } catch (e) {
      print("❌ Error renaming/tagging image: $e");
    }
  }
  // ----------------------------------------------------------------
  // 2. DELETE: Remove a photo and its line from the CSV
  // ----------------------------------------------------------------
  static Future<void> deleteImage({
    required String projectName,
    required String imagePath,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final File csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');

    try {
      // A. Delete the physical image file
      final File imageFile = File(imagePath);
      if (await imageFile.exists()) {
        await imageFile.delete();
      }

      // B. Remove line from CSV
      if (await csvFile.exists()) {
        List<String> lines = await csvFile.readAsLines();
        List<String> updatedLines = [];

        for (String line in lines) {
          // Only keep lines that DO NOT contain the deleted image path
          if (!line.contains(imagePath)) {
            updatedLines.add(line);
          }
        }

        // Write back the clean list
        await csvFile.writeAsString(updatedLines.join('\n'));
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ Error deleting image: $e");
      }
    }
  }

  // ----------------------------------------------------------------
  // 3. READ: Get all data (For the Map Page later)
  // ----------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> readCsvData(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final File csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');

    List<Map<String, dynamic>> dataPoints = [];

    if (await csvFile.exists()) {
      List<String> lines = await csvFile.readAsLines();

      // Start loop at 0 to skip the Header row
      for (int i = 0; i < lines.length; i++) {
        String line = lines[i];
        if (line.trim().isEmpty) continue;

        if (line.startsWith("image_path") || line.contains("latitude")) {
          continue;
        }

        List<String> parts = line.split(',');

        if (parts.length >= 4) {
          dataPoints.add({
            "path": parts[0],
            "lat": double.parse(parts[1]),
            "lng": double.parse(parts[2]),
            "time": parts[3],
            // Safety check: if CSV is old, it might not have column 4
            "class": parts.length > 4 ? parts[4].trim() : "Unclassified",
          });
        }
      }
    }
    return dataPoints;
  }

  // ----------------------------------------------------------------
  // 4. SYNC: Repair the CSV if it's missing rows for existing images
  // ----------------------------------------------------------------
  static Future<void> syncProjectData(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectName/images');
    final csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');
    final classFile = File('${appDir.path}/projects/$projectName/classes.json'); // 1. Path to classes

    if (!await projectDir.exists()) return;

    // ---------------------------------------------------------
    // 2. LOAD VALID CLASSES INTO A SET
    // ---------------------------------------------------------
    Set<String> validClassNames = {};
    if (await classFile.exists()) {
      try {
        List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
        for (var item in jsonList) {
          validClassNames.add(item['name']);
        }
      } catch (e) {
        print("Error reading classes json: $e");
      }
    }

    // 3. Get Physical Images
    List<File> images = projectDir.listSync()
        .where((item) => item.path.endsWith('.jpg') || item.path.endsWith('.png'))
        .map((item) => File(item.path))
        .toList();

    // 4. Get Existing CSV Data
    List<String> existingLines = [];
    if (await csvFile.exists()) {
      existingLines = await csvFile.readAsLines();
    }

    Set<String> recordedFilenames = {};
    for (String line in existingLines) {
      if (line.trim().isEmpty) continue;
      String path = line.split(',')[0];
      String filename = path.split(Platform.pathSeparator).last;
      recordedFilenames.add(filename);
    }

    List<String> newRowsToAdd = [];
    bool needsUpdate = false;

    // 5. Loop and Recover
    for (File img in images) {
      String filename = img.path.split(Platform.pathSeparator).last;

      if (!recordedFilenames.contains(filename)) {
        print("⚠️ Recovering data for: $filename");

        String lat = "0.0";
        String lng = "0.0";
        String recoveredClass = "Unclassified"; // Default

        try {
          final exif = await Exif.fromPath(img.path);
          final latLong = await exif.getLatLong();

          if (latLong != null) {
            lat = latLong.latitude.toString();
            lng = latLong.longitude.toString();
          }

          // --- CLASS VERIFICATION LOGIC ---
          final comment = await exif.getAttribute('UserComment');

          if (comment != null && comment.toString().isNotEmpty) {
            String rawClass = comment.toString();

            // CHECK: Is this class in our official list?
            if (validClassNames.contains(rawClass)) {
              recoveredClass = rawClass;
              print("   🏷️ Recovered Valid Class: $recoveredClass");
            } else {
              print("   🚫 Found unknown class '$rawClass'. Reverting to Unclassified.");
              recoveredClass = "Unclassified";
            }
          }
          // --------------------------------

          await exif.close();
        } catch (e) {
          print("   ⚠️ Error reading EXIF: $e");
        }

        String cleanPath = img.path.replaceAll(',', '');
        String time = img.lastModifiedSync().toIso8601String();

        newRowsToAdd.add("$cleanPath,$lat,$lng,$time,$recoveredClass");
        needsUpdate = true;
      }
    }

    // 6. Save Updates
    if (needsUpdate) {
      String dataBlock = newRowsToAdd.join('\n');
      if (existingLines.isNotEmpty && existingLines.last.isNotEmpty) {
        dataBlock = "\n$dataBlock";
      } else {
        dataBlock = "$dataBlock\n";
      }
      await csvFile.writeAsString(dataBlock, mode: FileMode.append);
      print("🔄 Recovery Complete. Added ${newRowsToAdd.length} rows.");
    }
  }

  // ----------------------------------------------------------------
  // 5. Embed GEODATA: Add GEODATA to EXIF Metadata of Image
  // ----------------------------------------------------------------


  // Update arguments to accept className
  // Update arguments to accept className
  static Future<void> embedMetadata({
    required String filePath,
    required double lat,
    required double lng,
    String? className, // <--- New Argument
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      final exif = await Exif.fromPath(filePath);

      final String latRef = lat >= 0 ? 'N' : 'S';
      final String lngRef = lng >= 0 ? 'E' : 'W';

      // Prepare attributes
      Map<String, Object> attributes = {
        'GPSLatitude': lat.abs(),
        'GPSLatitudeRef': latRef,
        'GPSLongitude': lng.abs(),
        'GPSLongitudeRef': lngRef,
      };

      // If we have a class, save it in the "UserComment" tag
      if (className != null) {
        attributes['UserComment'] = className;
      }

      await exif.writeAttributes(attributes);
      await exif.close();

    } catch (e) {
      print("⚠️ EXIF Error: $e");
    }
  }

  // ----------------------------------------------------------------
  // 6. CLASS MANAGEMENT
  // ----------------------------------------------------------------

  // A. Save a new Class Definition
  static Future<void> addClassDefinition(String projectName, String className, int colorValue) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/projects/$projectName/classes.json');

    List<dynamic> classes = [];
    if (await file.exists()) {
      classes = jsonDecode(await file.readAsString());
    }

    // Avoid duplicates
    if (!classes.any((c) => c['name'] == className)) {
      classes.add({'name': className, 'color': colorValue});
      await file.writeAsString(jsonEncode(classes));
    }
  }

  // B. Get all Classes
  static Future<List<Map<String, dynamic>>> getClasses(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/projects/$projectName/classes.json');

    if (await file.exists()) {
      // Decode and return as List of Maps
      return List<Map<String, dynamic>>.from(jsonDecode(await file.readAsString()));
    }
    return [];
  }

  // Shared helper to generate "Project_Class_N.jpg"
  static Future<String> generateNextFileName(Directory projectDir, String projectName, String className) async {
    // Sanitize inputs
    String cleanProject = projectName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    String cleanClass = className.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    if (cleanClass.isEmpty) cleanClass = "Unclassified";

    String baseName = "${cleanProject}_$cleanClass";
    int counter = 1;

    while (true) {
      String fileName = "${baseName}_$counter.jpg";
      File file = File('${projectDir.path}/$fileName');

      if (!await file.exists()) {
        return fileName;
      }
      counter++;
    }
  }




}