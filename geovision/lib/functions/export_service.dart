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

      // --- 1. FETCH METADATA & CONFIG (GeoJSON Based) ---
      debugPrint("🔍 Reading Project Data from GeoJSON...");
      // This now calls the GeoJSON-compatible version of readCsvData
      final geoData = await MetadataService.readCsvData(projectName);
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

      for (int i = 0; i < geoData.length; i++) {
        var row = geoData[i];
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

        if (imgWidth <= 0 || imgHeight <= 0) {
          debugPrint("⚠️ Skipping invalid image: $filename");
          continue;
        }

        images.add({
          "id": imageId,
          "width": imgWidth,
          "height": imgHeight,
          "file_name": filename,
          "date_captured": row['time'] ?? ""
        });

        // BRANCH: CLASSIFICATION
        if (projectType == 'classification') {
          String? label = row['class']?.toString();

          if (label != null && label.isNotEmpty && label != "Unclassified") {
            if (!classToId.containsKey(label)) {
              classToId[label] = nextCatId;
              categories.add({"id": nextCatId, "name": label, "supercategory": "object"});
              nextCatId++;
            }

            int catId = classToId[label]!;

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
        // BRANCH: SEGMENTATION
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

      // --- 4. WRITE FINAL COCO JSON ---
      final fullCocoJson = {
        "info": {
          "description": description.isNotEmpty ? description : "$projectName GeoVision Export.",
          "year": DateTime.now().year,
          "version": "1.0.0",
          "contributor": author,
          "date_created": DateTime.now().toIso8601String(),
          "url": "https://github.com/Blltz-0/GeoVision",
        },
        "licenses": [{"id": 1, "name": "CC BY 4.0", "url": "https://creativecommons.org/licenses/by/4.0/"}],
        "images": images,
        "annotations": annotations,
        "categories": categories
      };

      final cocoFile = File('${sourceDir.path}/_annotations.coco.json');
      await cocoFile.writeAsString(jsonEncode(fullCocoJson));
      tempFiles.add(cocoFile);

      // --- 5. GENERATE MAPS ---
      List<Map<String, double>> points = geoData.map((e) => {
        'lat': (e['lat'] as num).toDouble(),
        'lng': (e['lng'] as num).toDouble()
      }).toList();

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
      final readmeFile = File('${sourceDir.path}/README.txt');
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}";

      final StringBuffer readmeBuffer = StringBuffer();
      readmeBuffer.writeln("PROJECT NAME: $projectName");
      readmeBuffer.writeln("GENERATED ON: $dateStr");
      readmeBuffer.writeln("AUTHOR:       $author");
      readmeBuffer.writeln("==================================================");
      readmeBuffer.writeln("");
      readmeBuffer.writeln("DIRECTORY STRUCTURE");
      readmeBuffer.writeln(" ├── _annotations.coco.json (Master COCO Labels)");
      readmeBuffer.writeln(" ├── project_data.geojson   (Standard GIS Metadata)");
      readmeBuffer.writeln(" ├── images/                (Source Images)");
      readmeBuffer.writeln(" ├── map_overview_X.png      (Location Previews)");

      await readmeFile.writeAsString(readmeBuffer.toString());
      tempFiles.add(readmeFile);

      // --- 7. ZIP AND SHARE ---
      final File zipFile = File(zipPath);
      if (await zipFile.exists()) await zipFile.delete();

      await compute(_zipInBackground, [sourceDir.path, zipPath]);

      if (await zipFile.exists() && await zipFile.length() > 0) {
        await Share.shareXFiles([XFile(zipPath)], text: 'GeoVision Export: $projectName');
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

// --- ISOLATE FUNCTIONS ---
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

    final List<String> excludedFiles = [
      'last_opened.txt',
      'project_type.txt',
      'author.txt',
      'description.txt',
      'upload_history.json',
      'classes.json',
      'labels.json',
      'project_data.csv', // Exclude legacy CSV
      'project_map_overview.png',
      'map_overview.png',
      'map_overview_region.png',
    ];

    for (var entity in entities) {
      if (entity is File) {
        String fileName = entity.path.split(Platform.pathSeparator).last;
        if (fileName.startsWith('.')) continue;

        String lowerName = fileName.toLowerCase();

        if (excludedFiles.contains(lowerName)) continue;

        // Exclude the raw annotation folder contents
        if (entity.path.contains('${Platform.pathSeparator}annotation${Platform.pathSeparator}')) {
          continue;
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