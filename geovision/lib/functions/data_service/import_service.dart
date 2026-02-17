import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'; // Required for compute
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'metadata_handle.dart';

class ImportService {
  static Future<bool> executeImport(BuildContext context, FilePickerResult result) async {
    final String zipPath = result.files.single.path!;
    final String baseProjectName = result.files.single.name
        .replaceAll('.zip', '')
        .replaceAll('_COCO_Export', '');

    final appDir = await getApplicationDocumentsDirectory();
    final String projectsRoot = '${appDir.path}/projects';

    try {
      // Run the heavy work in the background
      final bool success = await compute(_backgroundImportTask, {
        'zipPath': zipPath,
        'projectsRoot': projectsRoot,
        'baseProjectName': baseProjectName,
      });

      if (success) {
        // After isolate finishes, rebuild the metadata index on the main thread
        // because MetadataService likely needs database/path access
        await MetadataService.rebuildProjectData(baseProjectName);
      }

      return success;
    } catch (e) {
      debugPrint("❌ ISOLATE IMPORT ERROR: $e");
      return false;
    }
  }
}

Future<bool> _backgroundImportTask(Map<String, String> params) async {
  final String zipPath = params['zipPath']!;
  final String projectsRoot = params['projectsRoot']!;
  final String baseProjectName = params['baseProjectName']!;

  String projectName = baseProjectName;
  String finalPath = '$projectsRoot/$projectName';

  try {
    final projectDir = Directory(finalPath);
    if (projectDir.existsSync()) {
      projectName = "${projectName}_${DateTime.now().millisecondsSinceEpoch}";
      finalPath = '$projectsRoot/$projectName';
    }

    final dir = await Directory(finalPath).create(recursive: true);

    // 1. EXTRACT ZIP
    final inputStream = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeStream(inputStream);

    for (final file in archive) {
      if (file.isFile) {
        final outFile = File('${dir.path}/${file.name}');
        outFile.createSync(recursive: true);
        final outputStream = OutputFileStream(outFile.path);
        file.writeContent(outputStream);
        outputStream.closeSync();
      }
    }
    inputStream.closeSync();

    // 2. DETECT TYPE
    String projectType = 'classification';
    final readmeFile = File('${dir.path}/README.txt');
    if (readmeFile.existsSync()) {
      final content = readmeFile.readAsStringSync();
      if (content.contains("Type: Image Segmentation")) projectType = 'segmentation';
      final authorMatch = RegExp(r"AUTHOR:\s+(.*)").firstMatch(content);
      if (authorMatch != null) {
        final author = authorMatch.group(1)?.trim() ?? "GeoVisionTagger";
        await File('${dir.path}/author.txt').writeAsString(author);
      }
      final descMatch = RegExp(r"DESCRIPTION\s+-+\s+([\s\S]*?)\n\nDATASET INFORMATION", multiLine: true)
          .firstMatch(content);
      if (descMatch != null) {
        final description = descMatch.group(1)?.trim() ?? "";
        if (description.isNotEmpty) {
          await File('${dir.path}/description.txt').writeAsString(description);
        }
      }



    }
    File('${dir.path}/project_type.txt').writeAsStringSync(projectType);

    // 3. RECONSTRUCT ANNOTATIONS
    final cocoFile = File('${dir.path}/_annotations.coco.json');
    if (cocoFile.existsSync()) {
      final Map<String, dynamic> cocoData = jsonDecode(cocoFile.readAsStringSync());
      final categories = cocoData['categories'] ?? [];
      final String metaFileName = (projectType == 'segmentation') ? 'labels.json' : 'classes.json';

      Map<int, String> categoryNames = {for (var c in categories) c['id']: c['name'].toString()};

      List mapped = categories.where((c) => c['name'].toString().toLowerCase() != 'unclassified').map((c) => {
        'name': c['name'],
        'color': _getColorForName(c['name'].toString()),
      }).toList();

      File('${dir.path}/$metaFileName').writeAsStringSync(jsonEncode(mapped));

      if (projectType == 'segmentation') {
        final annDir = Directory('${dir.path}/annotation')..createSync();
        final images = cocoData['images'] ?? [];
        final annotations = cocoData['annotations'] ?? [];

        for (var image in images) {
          final String fileName = image['file_name'].toString();
          final String baseName = fileName.contains('.') ? fileName.split('.').first : fileName;
          final imageAnns = annotations.where((a) => a['image_id'] == image['id']).toList();

          if (imageAnns.isEmpty) continue;

          List reconstructed = [];
          for (int j = 0; j < imageAnns.length; j++) {
            final ann = imageAnns[j];
            final labelName = categoryNames[ann['category_id']] ?? "Unclassified";
            final colorInt = _getColorForName(labelName);

// COCO 'segmentation' is a List of Lists: [[poly1], [poly2]]
            List<dynamic> allSegments = (ann['segmentation'] is List) ? ann['segmentation'] : [];
            List<Map<String, dynamic>> reconstructedStrokes = [];

            for (var seg in allSegments) {
              if (seg is! List) continue;

              List<List<double>> points = [];
              for (int k = 0; k < seg.length; k += 2) {
                points.add([(seg[k] as num).toDouble(), (seg[k + 1] as num).toDouble()]);
              }

              // Polygon must be closed to render correctly as a 'fill'
              if (points.isNotEmpty && (points.first[0] != points.last[0] || points.first[1] != points.last[1])) {
                points.add([points.first[0], points.first[1]]);
              }

              if (points.isNotEmpty) {
                reconstructedStrokes.add({
                  "p": points,
                  "c": colorInt,
                  "w": 3.0,
                  "e": false,
                  "f": true // Imported COCO segments are always filled polygons
                });
              }
            }

            if (reconstructedStrokes.isNotEmpty) {
              reconstructed.add({
                // Use a more robust unique ID to avoid collisions
                "id": "import_${image['id']}_${ann['id']}",
                "name": "Layer ${reconstructed.length + 1}",
                "labelName": labelName,
                "labelColor": colorInt,
                "isVisible": true,
                "isLocked": false,
                "strokes": reconstructedStrokes // This now contains all disjoint parts
              });
            }

          if (reconstructed.isNotEmpty) {
            File('${annDir.path}/${baseName}_data.json').writeAsStringSync(jsonEncode(reconstructed));
          }
        }
        }
      }
    }
    return true;
  } catch (e) {
    return false;
  }
}

int _getColorForName(String name) {
  final Random random = Random(name.hashCode);
  return Color.fromARGB(255, random.nextInt(150) + 100, random.nextInt(150) + 100, random.nextInt(150) + 100).value;
}