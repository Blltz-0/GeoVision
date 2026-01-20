import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'metadata_handle.dart';
import 'map_generator.dart';
import 'location_clusterer.dart';
import 'coco_converter.dart';
import '../components/annotation_layer.dart';

class ExportService {

  static Future<void> exportProject(String projectName) async {
    List<File> tempFiles = [];
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tempDir = await getTemporaryDirectory();

      final sourceDir = Directory('${appDir.path}/projects/$projectName');
      final imagesDir = Directory('${sourceDir.path}/images');
      final annotationDir = Directory('${sourceDir.path}/annotation');
      final zipPath = '${tempDir.path}/${projectName}_COCO_Export.zip';

      // --- 1. FETCH METADATA & CONFIG ---
      debugPrint("🔍 Reading Project Data...");
      final csvData = await MetadataService.readCsvData(projectName);
      final projectClasses = await MetadataService.getClasses(projectName);

      // Read Project Type
      String projectType = 'classification';
      final typeFile = File('${sourceDir.path}/project_type.txt');
      if (await typeFile.exists()) {
        projectType = (await typeFile.readAsString()).trim();
      }

      // Read Author
      String author = "GeoVisionTagger";
      final authorFile = File('${sourceDir.path}/author.txt');
      if (await authorFile.exists()) {
        final text = (await authorFile.readAsString()).trim();
        if (text.isNotEmpty) author = text;
      }

      // Read Description
      String description = "";
      final descFile = File('${sourceDir.path}/description.txt');
      if (await descFile.exists()) {
        description = (await descFile.readAsString()).trim();
      }

      // --- 2. INITIALIZE CATEGORIES ---
      Map<String, int> classToId = {};
      List<Map<String, dynamic>> categories = [];
      int nextCatId = 1;

      // Add explicit classes
      for (var c in projectClasses) {
        String name = c['name'];
        if (name.toLowerCase() == 'unclassified') continue;

        if (!classToId.containsKey(name)) {
          classToId[name] = nextCatId;
          categories.add({"id": nextCatId, "name": name, "supercategory": "object"});
          nextCatId++;
        }
      }

      // --- 3. PROCESS IMAGES ---
      List<Map<String, dynamic>> images = [];
      List<Map<String, dynamic>> annotations = [];
      int annotationIdCounter = 1;

      for (int i = 0; i < csvData.length; i++) {
        var row = csvData[i];
        String originalPath = row['path'].toString();
        String filename = originalPath.split(Platform.pathSeparator).last;
        int imageId = i + 1;

        File imageFile = File(originalPath);
        if (!await imageFile.exists()) {
          imageFile = File('${imagesDir.path}/$filename');
        }

        int imgWidth = 0;
        int imgHeight = 0;
        Size imageSize = Size.zero;

        if (await imageFile.exists()) {
          try {
            final bytes = await imageFile.readAsBytes();
            final decodedImg = await decodeImageFromList(bytes);
            imgWidth = decodedImg.width;
            imgHeight = decodedImg.height;
            imageSize = Size(imgWidth.toDouble(), imgHeight.toDouble());
          } catch (_) {}
        }

        // Skip zero-size images
        if (imgWidth <= 0 || imgHeight <= 0) {
          debugPrint("⚠️ Skipping zero-size or invalid image: $filename");
          continue;
        }

        images.add({
          "id": imageId,
          "width": imgWidth,
          "height": imgHeight,
          "file_name": filename,
          "date_captured": row['time'] ?? ""
        });

        // ============================================================
        // BRANCH: CLASSIFICATION MODE
        // ============================================================
        if (projectType == 'classification') {
          String? label = row['class']?.toString();

          if (label != null && label.isNotEmpty && label != "Unclassified") {
            if (!classToId.containsKey(label)) {
              classToId[label] = nextCatId;
              categories.add({"id": nextCatId, "name": label, "supercategory": "object"});
              nextCatId++;
            }

            int catId = classToId[label]!;

            // Full Image BBox for Classification
            annotations.add({
              "id": annotationIdCounter++,
              "image_id": imageId,
              "category_id": catId,
              "bbox": [0, 0, imgWidth, imgHeight],
              "area": imgWidth * imgHeight,
              "segmentation": [],
              "iscrowd": 0
            });
          }
        }
        // ============================================================
        // BRANCH: SEGMENTATION MODE
        // ============================================================
        else {
          String baseName = filename.split('.').first;
          File layerFile = File('${annotationDir.path}/${baseName}_data.json');

          if (await layerFile.exists()) {
            try {
              String content = await layerFile.readAsString();
              List<dynamic> jsonList = jsonDecode(content);
              List<AnnotationLayer> layers = jsonList.map((j) => AnnotationLayer.fromJson(j)).toList();

              for (var layer in layers) {
                if (!layer.isVisible || layer.strokes.isEmpty) continue;

                String labelName = layer.labelName ?? "Unclassified";

                if (!classToId.containsKey(labelName)) {
                  classToId[labelName] = nextCatId;
                  categories.add({"id": nextCatId, "name": labelName, "supercategory": "object"});
                  nextCatId++;
                }

                int catId = classToId[labelName]!;
                await Future.delayed(const Duration(milliseconds: 5));

                final annotationMap = await CocoConversionService.generateAnnotationForLayer(
                  layer: layer,
                  imageSize: imageSize,
                  imageId: imageId,
                  annotationId: annotationIdCounter++,
                  categoryId: catId,
                );

                if (annotationMap != null) {
                  annotations.add(annotationMap);
                }
              }
            } catch (e) { /* Ignore */ }
          }
        }
      }

      // --- 4. WRITE FINAL JSON ---
      final fullCocoJson = {
        "info": {
          "description": description.isNotEmpty
              ? description
              : "$projectName dataset generated using the GeoVisionTagger mobile application.",
          "year": DateTime.now().year,
          "version": "1.0.0",
          "contributor": author,
          "date_created": DateTime.now().toIso8601String(),
          "url": "https://github.com/Blltz-0/GeoVision",
          "source": "https://github.com/Blltz-0/GeoVision"
        },
        "licenses": [
          {
            "id": 1,
            "name": "CC BY 4.0",
            "url": "https://creativecommons.org/licenses/by/4.0/"
          }
        ],
        "images": images,
        "annotations": annotations,
        "categories": categories
      };

      final cocoFile = File('${sourceDir.path}/_annotations.coco.json');
      await cocoFile.writeAsString(jsonEncode(fullCocoJson));
      tempFiles.add(cocoFile);

      // --- 5. GENERATE MAPS ---
      // We explicitly create files named 'map_overview_X.png'
      List<Map<String, double>> points = [];
      for (var row in csvData) {
        double lat = double.tryParse(row['lat'].toString()) ?? 0.0;
        double lng = double.tryParse(row['lng'].toString()) ?? 0.0;
        if (lat.abs() > 0.1) points.add({'lat': lat, 'lng': lng});
      }

      if (points.isNotEmpty) {
        var clusters = LocationClusterer.clusterPoints(points, 500.0);
        for (int i = 0; i < clusters.length; i++) {
          final mapImg = await MapCompositor.generateFinalMap(clusters[i]);
          if (mapImg != null) {
            final mapPath = '${sourceDir.path}/map_overview_${i + 1}.png';
            final pngBytes = await compute(_encodePngInBackground, mapImg);
            final mapFile = File(mapPath);
            await mapFile.writeAsBytes(pngBytes);
            tempFiles.add(mapFile);
          }
        }
      }

      // --- 6. CREATE README.txt ---
      debugPrint("📄 Generating README...");
      final readmeFile = File('${sourceDir.path}/README.txt');
      List<String> categoryNames = categories.map((e) => e['name'].toString()).toList();
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')} ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";

      final StringBuffer readmeBuffer = StringBuffer();
      readmeBuffer.writeln("PROJECT NAME: $projectName");
      readmeBuffer.writeln("GENERATED ON: $dateStr");
      readmeBuffer.writeln("AUTHOR:       $author");
      readmeBuffer.writeln("SOURCE TOOL:  https://github.com/Blltz-0/GeoVision");
      readmeBuffer.writeln("DATA LICENSE: CC BY 4.0 (Free to use and modify with attribution)");
      readmeBuffer.writeln("==================================================");
      readmeBuffer.writeln("");

      if (description.isNotEmpty) {
        readmeBuffer.writeln("DESCRIPTION");
        readmeBuffer.writeln("-----------");
        readmeBuffer.writeln(description);
        readmeBuffer.writeln("");
      }

      readmeBuffer.writeln("DATASET INFORMATION");
      readmeBuffer.writeln("-------------------");
      if (projectType == 'segmentation') {
        readmeBuffer.writeln("Type: Image Segmentation");
        readmeBuffer.writeln("Format: COCO (Polygon Masks)");
      } else {
        readmeBuffer.writeln("Type: Image Classification");
        readmeBuffer.writeln("Format: COCO (Full-Image Bounding Boxes)");
      }
      readmeBuffer.writeln("Total Images Exported: ${images.length}");
      readmeBuffer.writeln("");

      readmeBuffer.writeln("DIRECTORY STRUCTURE");
      readmeBuffer.writeln("-------------------");
      readmeBuffer.writeln("/");
      readmeBuffer.writeln(" ├── _annotations.coco.json");
      readmeBuffer.writeln(" │    -> The Master Dataset file (COCO Standard).");
      readmeBuffer.writeln(" │");
      readmeBuffer.writeln(" ├── project_data.csv");
      readmeBuffer.writeln(" │    -> Raw metadata (GPS, Timestamp, Labels).");
      readmeBuffer.writeln(" │");
      readmeBuffer.writeln(" ├── images/");
      readmeBuffer.writeln(" │    -> Source images.");
      readmeBuffer.writeln("");
      readmeBuffer.writeln("Generated by GeoVisionTagger");

      await readmeFile.writeAsString(readmeBuffer.toString());
      tempFiles.add(readmeFile);

      // --- 7. ZIP (WITH STRICT FILTERING) ---
      debugPrint("📦 Zipping Project...");
      final File zipFile = File(zipPath);
      if (await zipFile.exists()) await zipFile.delete();

      await compute(_zipInBackground, [sourceDir.path, zipPath]);

      if (await zipFile.exists() && await zipFile.length() > 0) {
        await Share.shareXFiles([XFile(zipPath)], text: 'COCO Export: $projectName');
      } else {
        throw Exception("Zip file failed.");
      }

    } catch (e, stack) {
      debugPrint("❌ EXPORT ERROR: $e");
      debugPrint(stack.toString());
      rethrow;
    } finally {
      for (var f in tempFiles) {
        if (await f.exists()) await f.delete();
      }
    }
  }
}

// --- ISOLATE FUNCTIONS (With updated exclusions) ---
Uint8List _encodePngInBackground(img.Image image) {
  return img.encodePng(image);
}

void _zipInBackground(List<String> paths) {
  final String sourcePath = paths[0];
  final String destPath = paths[1];
  try {
    final sourceDir = Directory(sourcePath);
    final archive = Archive();
    if (!sourceDir.existsSync()) return;

    final entities = sourceDir.listSync(recursive: true);

    // --- FILES TO EXCLUDE ---
    final List<String> excludedFiles = [
      // App config files
      'last_opened.txt',
      'project_type.txt',
      'author.txt',
      'description.txt',
      'upload_history.json',
      'classes.json',
      'labels.json',
      // Redundant or temp files explicitly mentioned by user
      'data.csv',                // Redundant, we use project_data.csv
      'project_map_overview.png', // The black/failed map
      'map_overview.png',         // Generic map (we use map_overview_1.png)
      'map_overview_region.png',  // Redundant region map
    ];

    for (var entity in entities) {
      if (entity is File) {
        String fileName = entity.path.split(Platform.pathSeparator).last;
        if (fileName.startsWith('.')) continue;

        String lowerName = fileName.toLowerCase();

        // 1. Check strict exclusion list
        if (excludedFiles.contains(lowerName)) {
          continue;
        }

        // 2. Exclude internal annotation JSONs (We only want the master COCO file)
        if (entity.path.contains('${Platform.pathSeparator}annotation${Platform.pathSeparator}')) {
          if (lowerName.endsWith('.json')) {
            continue;
          }
        }

        String relativePath = entity.path.replaceFirst(sourcePath, '');
        while (relativePath.startsWith(Platform.pathSeparator)) {
          relativePath = relativePath.substring(1);
        }

        List<int> fileBytes = entity.readAsBytesSync();
        final archiveFile = ArchiveFile(relativePath, fileBytes.length, fileBytes);
        archive.addFile(archiveFile);
      }
    }

    final encoder = ZipEncoder();
    final List<int> encodedBytes = encoder.encode(archive);
    File(destPath).writeAsBytesSync(encodedBytes);
  } catch (e) {
    debugPrint("Zip Error: $e");
  }
}