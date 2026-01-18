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

      // --- 1. FETCH METADATA ---
      debugPrint("🔍 Reading Project Data...");
      final csvData = await MetadataService.readCsvData(projectName);
      final projectClasses = await MetadataService.getClasses(projectName);

      // --- 2a. INITIALIZE CATEGORY MAP ---
      Map<String, int> classToId = {};
      List<Map<String, dynamic>> categories = [];
      int nextCatId = 1;

      // Add "Unclassified" first
      classToId['Unclassified'] = 999;
      categories.add({"id": 999, "name": "Unclassified", "supercategory": "misc"});

      // Add explicit classes
      for (var c in projectClasses) {
        String name = c['name'];
        if (!classToId.containsKey(name)) {
          classToId[name] = nextCatId;
          categories.add({"id": nextCatId, "name": name, "supercategory": "object"});
          nextCatId++;
        }
      }

      // --- 2b. DYNAMIC CLASS DISCOVERY ---
      debugPrint("🔍 Scanning layers for dynamic labels...");
      if (await annotationDir.exists()) {
        final annotationFiles = annotationDir.listSync().whereType<File>().where((f) => f.path.endsWith('_data.json'));

        for (var file in annotationFiles) {
          try {
            String content = await file.readAsString();
            List<dynamic> jsonList = jsonDecode(content);
            for (var j in jsonList) {
              String? label = j['labelName'];
              if (label != null && label.isNotEmpty && !classToId.containsKey(label)) {
                debugPrint("🆕 Discovered new class: $label");
                classToId[label] = nextCatId;
                categories.add({"id": nextCatId, "name": label, "supercategory": "object"});
                nextCatId++;
              }
            }
          } catch (e) {
            // Ignore bad files
          }
        }
      }

      // --- 3. PROCESS IMAGES ---
      List<Map<String, dynamic>> images = [];
      List<Map<String, dynamic>> annotations = [];
      int annotationIdCounter = 1;

      debugPrint("🔍 Processing ${csvData.length} images...");

      for (int i = 0; i < csvData.length; i++) {
        var row = csvData[i];
        String originalPath = row['path'].toString();
        String filename = originalPath.split(Platform.pathSeparator).last;
        int imageId = i + 1;

        // Path & Dimensions Logic
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

        images.add({
          "id": imageId,
          "width": imgWidth,
          "height": imgHeight,
          "file_name": filename,
          "date_captured": row['time'] ?? ""
        });

        // --- PROCESSING ANNOTATIONS ---
        String baseName = filename.split('.').first;
        File layerFile = File('${annotationDir.path}/${baseName}_data.json');
        bool hasPainting = false;

        if (await layerFile.exists() && imgWidth > 0) {
          try {
            String content = await layerFile.readAsString();
            List<dynamic> jsonList = jsonDecode(content);
            List<AnnotationLayer> layers = jsonList.map((j) => AnnotationLayer.fromJson(j)).toList();

            for (var layer in layers) {
              if (!layer.isVisible || layer.strokes.isEmpty) continue;

              String labelName = layer.labelName ?? "Unclassified";
              int catId = classToId[labelName] ?? 999;

              await Future.delayed(Duration(milliseconds: 10));

              final annotationMap = await CocoConversionService.generateAnnotationForLayer(
                layer: layer,
                imageSize: imageSize,
                imageId: imageId,
                annotationId: annotationIdCounter++,
                categoryId: catId,
              );

              if (annotationMap != null) {
                annotations.add(annotationMap);
                hasPainting = true;
              }
            }
          } catch (e) {
            debugPrint("❌ Error converting paint data for $filename: $e");
          }
        }

        if (!hasPainting) {
          annotations.add({
            "id": annotationIdCounter++,
            "image_id": imageId,
            "category_id": 999,
            "iscrowd": 0,
            "area": (imgWidth * imgHeight).toDouble(),
            "bbox": [],
            "segmentation": []
          });
        }
      }

      // --- 4. WRITE FINAL JSON ---
      final fullCocoJson = {
        "info": {
          "description": projectName,
          "year": DateTime.now().year,
          "version": "1.0",
          "contributor": "GeoVisionTagger",
          "date_created": DateTime.now().toIso8601String()
        },
        "licenses": [{"id": 1, "name": "Proprietary", "url": ""}],
        "images": images,
        "annotations": annotations,
        "categories": categories
      };

      final cocoFile = File('${sourceDir.path}/_annotations.coco.json');
      await cocoFile.writeAsString(jsonEncode(fullCocoJson));
      tempFiles.add(cocoFile);

      // --- 5. GENERATE MAPS (RESTORED) ---
      debugPrint("🗺️ Generating Maps...");

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

      // --- 6. ZIP ---
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
    int count = 0;

    for (var entity in entities) {
      if (entity is File) {
        String fileName = entity.path.split(Platform.pathSeparator).last;
        // Skip hidden files
        if (fileName.startsWith('.')) continue;

        // --- FILTERING (EXCLUDE FILES) ---
        String lowerName = fileName.toLowerCase();

        // 1. Skip system files
        if (lowerName == 'last_opened.txt' ||
            lowerName == 'project_type.txt' ||
            lowerName == 'upload_history.json' ||
            lowerName == 'classes.json' ||
            lowerName == 'labels.json') {
          continue;
        }

        // 2. Skip individual annotation JSONs inside the annotation folder
        // (We only want the PNG masks if you need them, or skip those too if you only want the Master COCO JSON)
        if (entity.path.contains('${Platform.pathSeparator}annotation${Platform.pathSeparator}')) {
          if (lowerName.endsWith('.json')) {
            // Skip individual JSONs (we have the Master COCO now)
            continue;
          }
        }

        String relativePath = entity.path.replaceFirst(sourcePath, '');
        // Clean leading slashes
        while (relativePath.startsWith(Platform.pathSeparator)) {
          relativePath = relativePath.substring(1);
        }

        // Synchronous read - robust against thread killing
        List<int> fileBytes = entity.readAsBytesSync();
        final archiveFile = ArchiveFile(relativePath, fileBytes.length, fileBytes);
        archive.addFile(archiveFile);
        count++;
      }
    }

    final encoder = ZipEncoder();
    final List<int> encodedBytes = encoder.encode(archive);

    File(destPath).writeAsBytesSync(encodedBytes);
    debugPrint("✅ Zip Saved. Files: $count");
    } catch (e) {
    debugPrint("Zip Error: $e");
  }
}