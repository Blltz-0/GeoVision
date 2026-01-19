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

      // --- 2a. INITIALIZE CATEGORY MAP ---
      Map<String, int> classToId = {};
      List<Map<String, dynamic>> categories = [];
      int nextCatId = 1;

      // REMOVED: classToId['Unclassified'] = 999;
      // REMOVED: categories.add({"id": 999 ...});

      // Add explicit classes
      for (var c in projectClasses) {
        String name = c['name'];
        // Ensure we don't add "Unclassified" as a valid category
        if (name.toLowerCase() == 'unclassified') continue;

        if (!classToId.containsKey(name)) {
          classToId[name] = nextCatId;
          categories.add({"id": nextCatId, "name": name, "supercategory": "object"});
          nextCatId++;
        }
      }

      // --- 2b. DYNAMIC CLASS DISCOVERY ---
      if (await annotationDir.exists()) {
        final annotationFiles = annotationDir.listSync().whereType<File>().where((f) => f.path.endsWith('_data.json'));
        for (var file in annotationFiles) {
          try {
            String content = await file.readAsString();
            List<dynamic> jsonList = jsonDecode(content);
            for (var j in jsonList) {
              String? label = j['labelName'];
              // Skip Unclassified, null, or empty labels
              if (label != null &&
                  label.isNotEmpty &&
                  label.toLowerCase() != 'unclassified' &&
                  !classToId.containsKey(label)) {

                classToId[label] = nextCatId;
                categories.add({"id": nextCatId, "name": label, "supercategory": "object"});
                nextCatId++;
              }
            }
          } catch (e) { /* Ignore */ }
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

        // NEW: Skip zero-size images
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

        // --- PROCESSING ANNOTATIONS ---
        String baseName = filename.split('.').first;
        File layerFile = File('${annotationDir.path}/${baseName}_data.json');

        if (await layerFile.exists()) {
          try {
            String content = await layerFile.readAsString();
            List<dynamic> jsonList = jsonDecode(content);
            List<AnnotationLayer> layers = jsonList.map((j) => AnnotationLayer.fromJson(j)).toList();

            for (var layer in layers) {
              // 1. Skip invisible or empty layers
              if (!layer.isVisible || layer.strokes.isEmpty) continue;

              String labelName = layer.labelName ?? "Unclassified";

              // 2. Skip Unclassified layers (Strict Export)
              if (!classToId.containsKey(labelName)) {
                debugPrint("⚠️ Skipping unclassified layer on image $filename");
                continue;
              }

              int catId = classToId[labelName]!;

              // Slight delay to prevent UI freeze on large exports
              await Future.delayed(const Duration(milliseconds: 5));

              final annotationMap = await CocoConversionService.generateAnnotationForLayer(
                layer: layer,
                imageSize: imageSize,
                imageId: imageId,
                annotationId: annotationIdCounter++,
                categoryId: catId,
              );

              // 3. Only add if valid (non-null and has segmentation data)
              if (annotationMap != null) {
                // Double check segmentation isn't empty inside map if needed,
                // but checking null is usually sufficient from CocoService
                annotations.add(annotationMap);
              }
            }
          } catch (e) { /* Ignore */ }
        }

        // REMOVED: The block that added a blank annotation with category_id 999
        // If 'hasPainting' was false, we now simply add NOTHING to annotations.
      }

      // --- 4. WRITE FINAL JSON ---
      final fullCocoJson = {
        "info": {
          "description": projectName,
          "year": DateTime.now().year,
          "version": "1.0",
          "contributor": author,
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

      // --- 5. GENERATE MAPS ---
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

      // A. Extract Clean Category Names
      List<String> categoryNames = [];

      File sourceFile;
      if (projectType == 'segmentation') {
        sourceFile = File('${sourceDir.path}/labels.json');
      } else {
        sourceFile = File('${sourceDir.path}/classes.json');
      }

      if (await sourceFile.exists()) {
        try {
          List<dynamic> list = jsonDecode(await sourceFile.readAsString());
          categoryNames = list.map((e) {
            if (e is Map) {
              return e['name']?.toString() ?? "Unknown";
            }
            return e.toString();
          }).toList();
        } catch (_) {}
      }

      // B. Format Date nicely (YYYY-MM-DD HH:MM)
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')} ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";

      // C. Check Annotation Folder
      bool includeAnnotationFolder = false;
      if (await annotationDir.exists()) {
        final entities = annotationDir.listSync();
        if (entities.any((e) => e is File && !e.path.toLowerCase().endsWith('.json'))) {
          includeAnnotationFolder = true;
        }
      }

      // D. Build Content
      final StringBuffer readmeBuffer = StringBuffer();

      readmeBuffer.writeln("PROJECT NAME: $projectName");
      readmeBuffer.writeln("GENERATED ON: $dateStr");
      readmeBuffer.writeln("AUTHOR:       $author");
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
        readmeBuffer.writeln("");
      } else {
        readmeBuffer.writeln("Type: Image Classification");
        readmeBuffer.writeln("Format: COCO (Categories)");
        readmeBuffer.writeln("");
      }
      readmeBuffer.writeln("Total Images Exported: ${images.length}");
      readmeBuffer.writeln("");

      readmeBuffer.writeln("DEFINED CATEGORIES (${categoryNames.length})");
      readmeBuffer.writeln("----------------------");
      if (categoryNames.isEmpty) {
        readmeBuffer.writeln("(No explicit categories defined. Using dynamic labels.)");
      } else {
        for (var name in categoryNames) {
          readmeBuffer.writeln("- $name");
        }
      }
      readmeBuffer.writeln("");

      readmeBuffer.writeln("DIRECTORY STRUCTURE & GUIDE");
      readmeBuffer.writeln("---------------------------");
      readmeBuffer.writeln("/");
      readmeBuffer.writeln(" ├── _annotations.coco.json");
      readmeBuffer.writeln(" │    -> The Master Dataset file. Compatible with YOLO, TensorFlow, PyTorch.");
      readmeBuffer.writeln(" │");
      readmeBuffer.writeln(" ├── project_data.csv");
      readmeBuffer.writeln(" │    -> Contains raw metadata: GPS coordinates, Timestamps, and file paths.");
      readmeBuffer.writeln(" │");
      readmeBuffer.writeln(" ├── map_overview_X.png");
      readmeBuffer.writeln(" │    -> Visual map clusters showing where images were taken.");
      readmeBuffer.writeln(" │");
      readmeBuffer.writeln(" ├── images/");
      readmeBuffer.writeln(" │    -> Contains all the source images.");

      if (includeAnnotationFolder) {
        readmeBuffer.writeln(" │");
        readmeBuffer.writeln(" └── annotation/");
        readmeBuffer.writeln("      -> Contains visual segmentation masks (PNG/JPG) for quick preview.");
      }

      readmeBuffer.writeln("");
      readmeBuffer.writeln("--------------------------------------------------");
      readmeBuffer.writeln("Generated by GeoVisionTagger");
      readmeBuffer.writeln("https://github.com/Blltz-0/GeoVision");

      await readmeFile.writeAsString(readmeBuffer.toString());
      tempFiles.add(readmeFile);

      // --- 7. ZIP ---
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

// --- ISOLATE FUNCTIONS (Unchanged) ---
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
        if (fileName.startsWith('.')) continue;

        String lowerName = fileName.toLowerCase();
        if (lowerName == 'last_opened.txt' ||
            lowerName == 'project_type.txt' ||
            lowerName == 'author.txt' ||
            lowerName == 'description.txt' ||
            lowerName == 'upload_history.json' ||
            lowerName == 'classes.json' ||
            lowerName == 'labels.json') {
          continue;
        }

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
        count++;
      }
    }

    final encoder = ZipEncoder();
    final List<int> encodedBytes = encoder.encode(archive);
    File(destPath).writeAsBytesSync(encodedBytes);
  } catch (e) {
    debugPrint("Zip Error: $e");
  }
}