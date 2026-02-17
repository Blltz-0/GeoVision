import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;
import '../maps/location_clusterer.dart';
import '../maps/map_generator.dart';

class MapExportService {
  /// Generates and shares high-res map images for a specific list of points
  static Future<void> shareFilteredMap({
    required String projectName,
    required List<Map<String, double>> points,
  }) async {
    if (points.isEmpty) return;

    try {
      final tempDir = await getTemporaryDirectory();

      // 1. Cluster the points specifically for this view
      // This ensures we don't get 100 separate images if points are close
      final clusters = await compute(_clusterPointsInBackground, {
        'points': points,
        'distance': 500.0,
      });

      List<XFile> filesToShare = [];

      // 2. Process clusters into images
      for (int i = 0; i < clusters.length; i++) {
        // Uses your existing MapCompositor logic
        final mapImg = await MapCompositor.generateFinalMap(clusters[i]);

        if (mapImg != null) {
          final mapPath = '${tempDir.path}/${projectName}_filtered_region_${i + 1}.png';

          // Encode PNG in background to keep UI smooth
          final pngBytes = await compute(_encodePngInBackground, mapImg);

          final mapFile = File(mapPath);
          await mapFile.writeAsBytes(pngBytes);
          filesToShare.add(XFile(mapPath));
        }
      }

      // 3. Trigger Share Sheet
      if (filesToShare.isNotEmpty) {
        await Share.shareXFiles(
            filesToShare,
            text: 'GeoVision Filtered Map: $projectName (${points.length} points)'
        );
      }
    } catch (e) {
      debugPrint("❌ MAP TAB EXPORT ERROR: $e");
    }
  }
}

List<List<Map<String, double>>> _clusterPointsInBackground(Map<String, dynamic> params) {
  return LocationClusterer.clusterPoints(params['points'], params['distance']);
}

Uint8List _encodePngInBackground(img.Image image) {
  return img.encodePng(image);
}