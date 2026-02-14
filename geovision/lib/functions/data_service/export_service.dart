import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../metadata_handle.dart';
import '../map_generator.dart';
import '../location_clusterer.dart';
import '../coco_converter.dart';
import '../../components/annotation_layer.dart';

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

      // --- 1. FETCH METADATA (Fast) ---
      final geoData = await MetadataService.readCsvData(projectName);
      final projectClasses = await MetadataService.getClasses(projectName);

      String projectType = 'classification';
      final typeFile = File('${sourceDir.path}/project_type.txt');
      if (await typeFile.exists()) {
        projectType = (await typeFile.readAsString()).trim();
      }

      String author = "GeoVisionTagger";
      final authorFile = File('${sourceDir.path}/author.txt');
      if (await authorFile.exists()) {
        final text = (await authorFile.readAsString()).trim();
        if (text.isNotEmpty) author = text;
      }

      String description = "";
      final descFile = File('${sourceDir.path}/description.txt');
      if (await descFile.exists()) {
        description = (await descFile.readAsString()).trim();
      }

      // --- 2. HEAVY PROCESSING (Isolate) ---
      // Moving the 1000+ image loop and dimension fetching to background
      final Map<String, dynamic> exportResults = await compute(_processCocoDataInBackground, {
        'geoData': geoData,
        'projectClasses': projectClasses,
        'projectType': projectType,
        'imagesDirPath': imagesDir.path,
        'annotationDirPath': annotationDir.path,
      });

      // --- 3. CONSTRUCT & SERIALIZE JSON (Isolate) ---
      final fullCocoJson = {
        "info": {
          "description": description.isNotEmpty ? description : "$projectName GeoVision Export.",
          "year": DateTime.now().year,
          "version": "1.0.0",
          "contributor": author,
          "date_created": DateTime.now().toIso8601String(),
          "url": "https://github.com/Blltz-0/GeoVision",
        },
        "licenses": [
          {"id": 1, "name": "CC BY 4.0", "url": "https://creativecommons.org/licenses/by/4.0/"}
        ],
        "images": exportResults['images'],
        "annotations": exportResults['annotations'],
        "categories": exportResults['categories']
      };

      // Encoding a massive 1000-image JSON on main thread causes the "Matrix4" lag
      final String jsonString = await compute(jsonEncode, fullCocoJson);
      final cocoFile = File('${sourceDir.path}/_annotations.coco.json');
      await cocoFile.writeAsString(jsonString);
      tempFiles.add(cocoFile);

      // --- 4. GENERATE MAPS ---
      List<Map<String, double>> points = geoData.map((e) => {
        'lat': (e['lat'] as num).toDouble(),
        'lng': (e['lng'] as num).toDouble()
      }).toList();

      if (points.isNotEmpty) {
        final clusters = await compute(_clusterPointsInBackground, {
          'points': points,
          'distance': 500.0,
        });

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

      // --- 5. README ---
      final readmeFile = File('${sourceDir.path}/README.txt');
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      final StringBuffer readmeBuffer = StringBuffer();
      readmeBuffer.writeln("PROJECT NAME: $projectName");
      readmeBuffer.writeln("GENERATED ON: $dateStr");
      readmeBuffer.writeln("AUTHOR:       $author");
      readmeBuffer.writeln("==================================================");
      readmeBuffer.writeln("DIRECTORY STRUCTURE");
      readmeBuffer.writeln(" ├── _annotations.coco.json");
      readmeBuffer.writeln(" ├── project_data.geojson");
      readmeBuffer.writeln(" ├── images/");
      readmeBuffer.writeln(" ├── map_overview_X.png");

      await readmeFile.writeAsString(readmeBuffer.toString());
      tempFiles.add(readmeFile);

      // --- 6. ZIP AND SHARE ---
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

/// Handles the massive loop of 1000+ images and annotations in the background.
Future<Map<String, dynamic>> _processCocoDataInBackground(Map<String, dynamic> params) async {
  final List<dynamic> geoData = params['geoData'];
  final List<dynamic> projectClasses = params['projectClasses'];
  final String projectType = params['projectType'];
  final String imagesDirPath = params['imagesDirPath'];
  final String annotationDirPath = params['annotationDirPath'];

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

  List<Map<String, dynamic>> images = [];
  List<Map<String, dynamic>> annotations = [];
  int annotationIdCounter = 1;

  for (int i = 0; i < geoData.length; i++) {
    var row = geoData[i];
    String originalPath = row['path'].toString();
    String filename = originalPath.split(Platform.pathSeparator).last;
    int imageId = i + 1;

    File imageFile = File(originalPath);
    if (!imageFile.existsSync()) {
      imageFile = File('$imagesDirPath/$filename');
    }

    if (!imageFile.existsSync()) continue;

    // Use a lighter way to get dimensions in Isolate using the 'image' package
    final Uint8List bytes = imageFile.readAsBytesSync();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) continue;

    int imgWidth = decoded.width;
    int imgHeight = decoded.height;

    images.add({
      "id": imageId,
      "width": imgWidth,
      "height": imgHeight,
      "file_name": filename,
      "date_captured": row['time'] ?? ""
    });

    if (projectType == 'classification') {
      String? label = row['class']?.toString();
      if (label != null && label.isNotEmpty && label != "Unclassified") {
        int catId = classToId[label] ?? 0;
        if (catId != 0) {
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
    } else {
      // Segmentation logic
      String baseName = filename.split('.').first;
      File layerFile = File('$annotationDirPath/${baseName}_data.json');

      if (layerFile.existsSync()) {
        String content = layerFile.readAsStringSync();
        List<dynamic> jsonList = jsonDecode(content);
        List<AnnotationLayer> layers = jsonList.map((j) => AnnotationLayer.fromJson(j)).toList();

        for (var layer in layers) {
          if (!layer.isVisible || layer.strokes.isEmpty) continue;
          String labelName = layer.labelName ?? "Unclassified";
          int catId = classToId[labelName] ?? 0;
          if (catId == 0) continue;

          // Note: If CocoConversionService uses heavy Vector Math,
          // ensure its methods are static/pure so they work here.
          final ann = await CocoConversionService.generateAnnotationForLayer(
            layer: layer,
            imageSize: Size(imgWidth.toDouble(), imgHeight.toDouble()),
            imageId: imageId,
            annotationId: annotationIdCounter++,
            categoryId: catId,
          );
          if (ann != null) annotations.add(ann);
        }
      }
    }
  }

  return {
    'images': images,
    'annotations': annotations,
    'categories': categories,
  };
}

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
      'last_opened.txt', 'project_type.txt', 'author.txt', 'description.txt',
      'upload_history.json', 'classes.json', 'labels.json', 'project_data.csv',
      'project_map_overview.png', 'map_overview.png', 'map_overview_region.png',
    ];

    for (var entity in entities) {
      if (entity is File) {
        String fileName = entity.path.split(Platform.pathSeparator).last;
        if (fileName.startsWith('.') || excludedFiles.contains(fileName.toLowerCase())) continue;
        if (entity.path.contains('${Platform.pathSeparator}annotation${Platform.pathSeparator}')) continue;

        String relativePath = entity.path.replaceFirst(sourcePath, '');
        while (relativePath.startsWith(Platform.pathSeparator)) {
          relativePath = relativePath.substring(1);
        }

        List<int> fileBytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(relativePath, fileBytes.length, fileBytes));
      }
    }
    final encoder = ZipEncoder();
    File(destPath).writeAsBytesSync(encoder.encode(archive)!);
  } catch (e) {
    debugPrint("Zip Error: $e");
  }
}

List<List<Map<String, double>>> _clusterPointsInBackground(Map<String, dynamic> params) {
  return LocationClusterer.clusterPoints(params['points'], params['distance']);
}