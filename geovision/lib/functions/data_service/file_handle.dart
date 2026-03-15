import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geovision/functions/data_service/file_directories.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'metadata_exif.dart';
import 'metadata_geojson.dart';

class MetadataFiles {
  static Future<void> deleteImage({
    required String projectName,
    required String imagePath,
    String projectType = 'classification'
  }) async {
    final File imageFile = File(imagePath);

    // 1. Evict from Flutter's cache so the old image stops showing, then delete physical file
    if (await imageFile.exists()) {
      await FileImage(imageFile).evict();
      await imageFile.delete();
    }

    final filename = p.basename(imagePath);
    await MetadataGeoJson.removeEntry(projectName, filename);

    // 2. Delete associated annotation files (JSON data and PNG layers)
    try {
      final String baseImageName = p.basenameWithoutExtension(imagePath);
      final parentDir = File(imagePath).parent.parent;
      final Directory annotationDir = Directory(p.join(parentDir.path, 'annotation'));

      if (await annotationDir.exists()) {
        final List<FileSystemEntity> files = annotationDir.listSync();
        for (var file in files) {
          if (file is File && p.basename(file.path).startsWith(baseImageName)) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint("Error deleting annotations: $e");
    }

    // 3. Remove from upload history
    try {
      final historyFile = await FileDirectories.getUploadHistoryFile(projectName);
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
      if (kDebugMode) {
        print("Error scanning directory index: $e");
      }
    }

    return maxCount;
  }

  // --- FILE RENAMING / TAGGING ---
  static Future<String> generateNextFileName(
      Directory projectDir,
      String projectName,
      String className,
      {String projectType = 'classification', Set<String>? existingNames, String ext = '.jpg'}
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
          ? "${cleanProject}_$counter$ext"
          : "${cleanProject}_${cleanClass}_$counter$ext";

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

      // A. If already correctly named, just update embedded EXIF and CSV
      if (oldFilename.startsWith("${cleanProject}_${cleanClass}_")) {
        await MetadataGeoJson.updateClassInCsv(projectName: projectName, imagePath: oldImagePath, newClassName: newClassName);
        try {
          await MetadataExif.embedMetadata(filePath: oldImagePath, lat: 0, lng: 0, className: newClassName, updateClassOnly: true);
        } catch (e) {
          debugPrint("Warning: Exif embedding failed: $e");
        }
        return oldImagePath;
      }

      // B. Determine correct file extension and generate path
      String ext = p.extension(oldImagePath);
      if (ext.isEmpty) ext = '.jpg';
      String newFileName = await generateNextFileName(projectDir, projectName, newClassName, projectType: projectType, ext: ext);
      String newImagePath = p.join(projectDir.path, newFileName);

      // 1. UPDATE CSV FIRST!
      // Do this BEFORE renaming the physical file so the database row perfectly updates
      // and timestamps are permanently preserved. Pass the FULL newImagePath.
      await MetadataGeoJson.updateClassInCsv(
        projectName: projectName,
        imagePath: oldImagePath,
        newImagePath: newImagePath,
        newClassName: newClassName,
      );

      // 2. NOW rename the physical file safely
      await oldFile.rename(newImagePath);

      // 3. Sync upload history map
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

      // 4. Safely embed metadata into the newly renamed file
      try {
        await MetadataExif.embedMetadata(filePath: newImagePath, lat: 0, lng: 0, className: newClassName, updateClassOnly: true);
      } catch (e) {
        debugPrint("Error embedding EXIF (non-fatal): $e");
      }

      // CRITICAL: We DO NOT call rebuildProjectData() here.
      // Our CSV was just perfectly updated. Rebuilding now risks corrupting it.

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