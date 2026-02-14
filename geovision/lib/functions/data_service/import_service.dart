import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../metadata_handle.dart';

class ImportService {
  static Future<bool> importProject(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result == null || result.files.single.path == null) return false;


      File zipFile = File(result.files.single.path!);
      String rawName = result.files.single.name.replaceAll('.zip', '');
      String projectName = rawName.replaceAll('_COCO_Export', '');

      final appDir = await getApplicationDocumentsDirectory();
      String finalPath = '${appDir.path}/projects/$projectName';

      if (await Directory(finalPath).exists()) {
        projectName = "${projectName}_${DateTime.now().millisecondsSinceEpoch}";
        finalPath = '${appDir.path}/projects/$projectName';
      }

      final projectDir = await Directory(finalPath).create(recursive: true);
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        if (file.isFile) {
          final data = file.content as List<int>;
          File outFile = File('${projectDir.path}/${file.name}');
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        }
      }

      // --- 1. RECONSTRUCT CLASSES ---
      await _rebuildClasses(projectName, projectDir);

      // --- 2. RECONSTRUCT GEOJSON ---
      // We detect type based on folder contents or filename structure
      String projectType = 'classification';
      final annotationDir = Directory('${projectDir.path}/annotation');
      if (await annotationDir.exists()) {
        projectType = 'segmentation';
      }

      await MetadataService.rebuildProjectData(projectName, projectType: projectType);


      return true;
    } catch (e) {
      debugPrint("❌ IMPORT ERROR: $e");
      return false;
    }
  }

  static Future<void> _rebuildClasses(String projectName, Directory projectDir) async {
    Set<String> classNames = {};

    // Check for COCO file (Exported version uses _annotations.coco.json)
    final cocoFile = File('${projectDir.path}/_annotations.coco.json');
    if (await cocoFile.exists()) {
      try {
        final content = jsonDecode(await cocoFile.readAsString());
        final categories = content['categories'] as List;
        for (var cat in categories) {
          String name = cat['name'].toString();
          if (name.toLowerCase() != 'unclassified') classNames.add(name);
        }
      } catch (_) {}
    }

    // Supplemental scan of image filenames
    final imagesDir = Directory('${projectDir.path}/images');
    if (await imagesDir.exists()) {
      final entities = imagesDir.listSync();
      for (var entity in entities) {
        final filename = entity.path.split(Platform.pathSeparator).last;
        final parts = filename.split('_');
        if (parts.length >= 3) { // Expecting Project_Class_Counter.jpg
          String candidate = parts[1];
          if (candidate.toLowerCase() != "unclassified") classNames.add(candidate);
        }
      }
    }

    if (classNames.isNotEmpty) {
      List<Map<String, dynamic>> classList = classNames.map((name) => {
        'name': name,
        'color': _generateRandomColor().value,
      }).toList();

      final classFile = File('${projectDir.path}/classes.json');
      await classFile.writeAsString(jsonEncode(classList));
    }
  }

  static Color _generateRandomColor() {
    final Random random = Random();
    return Color.fromARGB(
        255,
        random.nextInt(156) + 50,
        random.nextInt(156) + 50,
        random.nextInt(156) + 50
    );
  }
}