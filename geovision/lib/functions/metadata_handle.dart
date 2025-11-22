import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';

class MetadataService {

  // ----------------------------------------------------------------
  // 1. APPEND: Save a new photo's data to the CSV
  // ----------------------------------------------------------------
  static Future<void> saveToCsv({
    required String projectName,
    required String imagePath,
    required Position? position,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final File csvFile = File('${appDir.path}/projects/$projectName/project_data.csv');

    // Prepare Data
    // Remove commas from path to prevent breaking the CSV columns
    String cleanPath = imagePath.replaceAll(',', '');
    String lat = position?.latitude.toString() ?? "0.0";
    String lng = position?.longitude.toString() ?? "0.0";
    String time = DateTime.now().toIso8601String();

    // Format: path,latitude,longitude,timestamp
    String newRow = "$cleanPath,$lat,$lng,$time\n";

    try {
      // Write Header if file is new
      if (!await csvFile.exists()) {
        await csvFile.writeAsString("image_path,latitude,longitude,timestamp\n");
      }

      // Append the new row
      await csvFile.writeAsString(newRow, mode: FileMode.append);

    } catch (e) {
      if (kDebugMode) {
        print("❌ Error saving CSV: $e");
      }
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
            "lat": double.tryParse(parts[1]) ?? 0.0,
            "lng": double.tryParse(parts[2]) ?? 0.0,
            "time": parts[3]
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

    if (!await projectDir.exists()) return;

    // 1. Get all physical images
    List<File> images = projectDir.listSync()
        .where((item) => item.path.endsWith('.jpg') || item.path.endsWith('.png'))
        .map((item) => File(item.path))
        .toList();

    // 2. Read existing CSV Data
    List<String> existingLines = [];
    if (await csvFile.exists()) {
      existingLines = await csvFile.readAsLines();
    }

    // 3. Find Missing Entries
    bool needsUpdate = false;

    // Create a temporary list of paths that are already in the CSV
    // We use a Set for faster lookup
    Set<String> recordedPaths = {};
    for (String line in existingLines) {
      if (line.isNotEmpty) {
        // Assume path is before the first comma
        String path = line.split(',')[0];
        // Normalize path just in case (filenames only)
        recordedPaths.add(path.split(Platform.pathSeparator).last);
      }
    }

    List<String> newRowsToAdd = [];

    for (File img in images) {
      String filename = img.path.split(Platform.pathSeparator).last;

      // If this image is NOT in our CSV records...
      if (!recordedPaths.contains(filename)) {

        // Create a default "Repair" row
        // We use the file's last modified time as the timestamp
        String cleanPath = img.path.replaceAll(',', '');
        String lat = "0.0"; // Lost data
        String lng = "0.0"; // Lost data
        String time = img.lastModifiedSync().toIso8601String();

        newRowsToAdd.add("$cleanPath,$lat,$lng,$time");
        needsUpdate = true;
      }
    }

    // 4. Append missing rows to CSV
    if (needsUpdate) {
      String dataBlock = newRowsToAdd.join('\n');
      // Ensure we start on a new line if file wasn't empty
      if (existingLines.isNotEmpty && existingLines.last.isNotEmpty) {
        dataBlock = "\n$dataBlock";
      } else if (existingLines.isNotEmpty && existingLines.last.isEmpty) {
        // If file ends with newline, just append
        dataBlock = dataBlock;
      } else {
        // If file is empty/new, add newline at end
        dataBlock = "$dataBlock\n";
      }

      await csvFile.writeAsString(dataBlock, mode: FileMode.append);
    }
  }

  // ----------------------------------------------------------------
  // 5. Embed GEODATA: Add GEODATA to EXIF Metadata of Image
  // ----------------------------------------------------------------


  static Future<void> embedLocationIntoImage(String filePath, double lat, double lng) async {
    final exif = await Exif.fromPath(filePath);

    // Write the attributes
    await exif.writeAttributes({
      'GPSLatitude': lat,
      'GPSLongitude': lng,
    });

    // Close the file to save changes
    await exif.close();
  }


}