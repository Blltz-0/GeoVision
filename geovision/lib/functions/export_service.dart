import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'metadata_handle.dart';
import 'map_generator.dart';
import 'location_clusterer.dart'; // Import the file you just made

class ExportService {
  static Future<void> exportProject(String projectName) async {
    print("🚀 STARTING SMART EXPORT for $projectName");

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sourceDir = Directory('${appDir.path}/projects/$projectName');
      final zipPath = '${appDir.path}/${projectName}_Export.zip';

      // 1. EXTRACT POINTS
      final csvData = await MetadataService.readCsvData(projectName);
      List<Map<String, double>> points = [];

      for (var row in csvData) {
        double? lat = double.tryParse(row['lat'].toString());
        double? lng = double.tryParse(row['lng'].toString());
        // Basic 0.0 check
        if (lat != null && lng != null && (lat.abs() > 0.1 || lng.abs() > 0.1)) {
          points.add({'lat': lat, 'lng': lng});
        }
      }

      // 2. CLUSTER POINTS (The Magic Fix)
      // Group points if they are within 500km of each other.
      // If > 500km, they get a separate map.
      print("🧩 Clustering points...");
      var clusters = LocationClusterer.clusterPoints(points, 500.0);
      print("   > Found ${clusters.length} distinct regions (e.g. countries).");

      // 3. GENERATE MAPS FOR EACH CLUSTER
      // We store generated map files in a list to add to zip later
      List<File> generatedMaps = [];

      for (int i = 0; i < clusters.length; i++) {
        var clusterPoints = clusters[i];
        String regionName = "region_${i + 1}"; // e.g., map_region_1.png

        print("🎨 Generating Map for Region ${i+1} (${clusterPoints.length} points)...");

        final img.Image? mapImg = await MapCompositor.generateFinalMap(clusterPoints);

        if (mapImg != null) {
          final mapPath = '${sourceDir.path}/map_overview_$regionName.png';
          final mapFile = File(mapPath);
          await mapFile.writeAsBytes(img.encodePng(mapImg));
          generatedMaps.add(mapFile);
          print("   ✅ Saved $regionName");
        }
      }

      // 4. CREATE ZIP
      print("📦 Zipping...");
      final zipFile = File(zipPath);
      if (zipFile.existsSync()) zipFile.deleteSync();

      var encoder = ZipFileEncoder();
      encoder.create(zipPath);

      // Add the project folder (images, csv)
      await encoder.addDirectory(sourceDir);

      // Ensure all generated maps are included (force add if addDirectory missed them)
      for (var mapFile in generatedMaps) {
        if (mapFile.existsSync()) {
          await encoder.addFile(mapFile);
        }
      }

      encoder.close();

      // 5. SHARE
      await Share.shareXFiles([XFile(zipPath)], text: 'Export: $projectName');

    } catch (e, stack) {
      print("❌ ERROR: $e");
      print(stack);
    }
  }
}