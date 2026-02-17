import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geovision/functions/data_service/file_directories.dart';
import 'package:path/path.dart' as p;
import 'metadata_exif.dart';
import 'metadata_geojson.dart';

class MetadataFiles {
  static Future<void> deleteImage({required String projectName, required String imagePath, String projectType = 'classification'}) async {
    final File imageFile = File(imagePath);
    if (await imageFile.exists()) await imageFile.delete();

    final filename = p.basename(imagePath);
    await MetadataGeoJson.removeEntry(projectName, filename);
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
      String currentFilename = p.basename(oldImagePath);

      if (currentFilename.startsWith("${cleanProject}_${cleanClass}_")) {
        // Just update metadata
        await MetadataGeoJson.updateClassInCsv(projectName: projectName, imagePath: oldImagePath, newClassName: newClassName);
        await MetadataExif.embedMetadata(filePath: oldImagePath, lat: 0, lng: 0, className: newClassName, updateClassOnly: true);
        return oldImagePath;
      }

      String newFileName = await generateNextFileName(projectDir, projectName, newClassName, projectType: projectType);
      String newImagePath = '${projectDir.path}/$newFileName';

      await oldFile.rename(newImagePath);

      // We must save the new entry to GeoJSON manually or rebuild.
      // Rebuild is safer to keep things in sync.
      await MetadataGeoJson.rebuildProjectData(projectName, projectType: projectType);

      // Re-embed metadata on new file
      await MetadataExif.embedMetadata(filePath: newImagePath, lat: 0, lng: 0, className: newClassName, updateClassOnly: true);

      return newImagePath;
    } catch (e) {
      debugPrint("❌ Error tagging image: $e");
      return null;
    }
  }
}