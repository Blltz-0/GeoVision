import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geovision/functions/data_service/file_directories.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../image/image_metadata.dart';
import 'metadata_exif.dart';
import 'metadata_geojson.dart';

class MetadataFiles {
  static Future<void> deleteImage({
    required String projectName,
    required String imagePath,
    String projectType = 'classification'
  }) async {
    final File imageFile = File(imagePath);
    if (await imageFile.exists()) await imageFile.delete();

    final filename = p.basename(imagePath);
    await MetadataGeoJson.removeEntry(projectName, filename);

    try {
      final historyFile = await FileDirectories.getUploadHistoryFile(projectName); // Using helper
      if (await historyFile.exists()) {
        final Map<String, dynamic> historyMap = jsonDecode(await historyFile.readAsString());
        if (historyMap.containsKey(filename)) {
          historyMap.remove(filename);
          await historyFile.writeAsString(jsonEncode(historyMap));
        }
      }
    } catch (e) {
      debugPrint("Error updating upload_history.json: $e");
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

    final projectDir = await FileDirectories.getProjectImageDir(projectName);
    final File oldFile = File(oldImagePath);
    if (!await oldFile.exists()) return null;

    try {
      String cleanProject = projectName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      String cleanClass = newClassName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      String oldFilename = p.basename(oldImagePath);

      if (oldFilename.startsWith("${cleanProject}_${cleanClass}_")) {
        // Just update metadata
        await MetadataGeoJson.updateClassInCsv(projectName: projectName, imagePath: oldImagePath, newClassName: newClassName);
        await MetadataExif.embedMetadata(filePath: oldImagePath, lat: 0, lng: 0, className: newClassName, updateClassOnly: true);
        return oldImagePath;
      }

      String newFileName = await generateNextFileName(projectDir, projectName, newClassName, projectType: projectType);
      String newImagePath = '${projectDir.path}/$newFileName';

      // 1. Rename the physical file
      await oldFile.rename(newImagePath);

      // 2. Update upload_history.json ONLY if the file was an upload (exists in history)
      try {
        final historyFile = await FileDirectories.getUploadHistoryFile(projectName);
        if (await historyFile.exists()) {
          final Map<String, dynamic> historyMap = jsonDecode(await historyFile.readAsString());
          if (historyMap.containsKey(oldFilename)) {
            historyMap[newFileName] = historyMap[oldFilename];
            historyMap.remove(oldFilename);
            await historyFile.writeAsString(jsonEncode(historyMap));
          }
        }
      } catch (e) {
        debugPrint("Error syncing history: $e");
      }

      await MetadataGeoJson.updateClassInCsv(
        projectName: projectName,
        imagePath: oldImagePath,   // Look for this name
        newImagePath: newImagePath, // Replace with this path
        newClassName: newClassName,
      );

      // 3. Rebuild Project Data & Embed Metadata
      await MetadataGeoJson.rebuildProjectData(projectName, projectType: projectType);
      await MetadataExif.embedMetadata(filePath: newImagePath, lat: 0, lng: 0, className: newClassName, updateClassOnly: true);

      return newImagePath;
    } catch (e) {
      debugPrint("❌ Error tagging image: $e");
      return null;
    }
  }

  static Future<File> _getHistoryFile(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/projects/$projectName/upload_history.json');
  }

  // Called when an image is deleted
  static Future<void> removeHistory(String projectName, String filename) async {
    try {
      final file = await _getHistoryFile(projectName);
      if (!await file.exists()) return;

      final Map<String, dynamic> history = jsonDecode(await file.readAsString());
      if (history.containsKey(filename)) {
        history.remove(filename);
        await file.writeAsString(jsonEncode(history));
        debugPrint("History: Removed $filename");
      }
    } catch (e) {
      debugPrint("Error removing from history: $e");
    }
  }

  // Called when an image is retagged (renamed)
  static Future<void> renameHistory(String projectName, String oldName, String newName) async {
    try {
      final file = await _getHistoryFile(projectName);
      if (!await file.exists()) return;

      final Map<String, dynamic> history = jsonDecode(await file.readAsString());
      if (history.containsKey(oldName)) {
        history[newName] = history[oldName];
        history.remove(oldName);
        await file.writeAsString(jsonEncode(history));
        debugPrint("History: Renamed $oldName to $newName");
      }
    } catch (e) {
      debugPrint("Error renaming in history: $e");
    }
  }
}