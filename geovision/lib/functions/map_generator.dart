import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

// Helper imports
import 'dart_kde.dart'; // The heatmap math file we just updated
import 'tile_math.dart'; // Your existing tile math helper

class MapCompositor {
  static const int tileSize = 256;

  // Safety Limit: Prevents "Out of Memory" crashes on large projects
  static const int maxDimension = 2500;

  /// Main function to download tiles and stitch the map
  static Future<img.Image?> generateFinalMap(List<Map<String, double>> points) async {
    if (points.isEmpty) return null;

    // ---------------------------------------------------------
    // 1. DETERMINE DATA BOUNDS (With Smart Context)
    // ---------------------------------------------------------
    double minLat = points.first['lat']!;
    double maxLat = points.first['lat']!;
    double minLng = points.first['lng']!;
    double maxLng = points.first['lng']!;

    for (var p in points) {
      if (p['lat']! < minLat) minLat = p['lat']!;
      if (p['lat']! > maxLat) maxLat = p['lat']!;
      if (p['lng']! < minLng) minLng = p['lng']!;
      if (p['lng']! > maxLng) maxLng = p['lng']!;
    }

    // ✅ SMART CONTEXT FIX:
    // If points are too close (e.g. 10m apart), the map looks weird/empty.
    // We enforce a minimum view of ~500m (approx 0.005 degrees) so you see streets.
    double latSpread = maxLat - minLat;
    double lngSpread = maxLng - minLng;
    const double minSpread = 0.005;

    if (latSpread < minSpread) {
      double center = (maxLat + minLat) / 2;
      minLat = center - (minSpread / 2);
      maxLat = center + (minSpread / 2);
    }
    if (lngSpread < minSpread) {
      double center = (maxLng + minLng) / 2;
      minLng = center - (minSpread / 2);
      maxLng = center + (minSpread / 2);
    }

    // Add a 10% aesthetic buffer so points aren't touching the edge
    double latBuffer = (maxLat - minLat) * 0.1;
    double lngBuffer = (maxLng - minLng) * 0.1;

    double dataMinLat = minLat - latBuffer;
    double dataMaxLat = maxLat + latBuffer;
    double dataMinLng = minLng - lngBuffer;
    double dataMaxLng = maxLng + lngBuffer;

    // ---------------------------------------------------------
    // 2. AUTO-CALCULATE ZOOM LEVEL
    // ---------------------------------------------------------
    // Start at Zoom 17 (Street Level) and zoom out if the image is too big for RAM.
    int zoom = 17;
    int width = 0;
    int height = 0;
    int startX = 0, endX = 0, startY = 0, endY = 0;


    while (true) {
      var tl = TileMath.getTileIndex(dataMaxLat, dataMinLng, zoom);
      var br = TileMath.getTileIndex(dataMinLat, dataMaxLng, zoom);

      startX = tl.x;
      endX = br.x;
      startY = tl.y;
      endY = br.y;

      width = (endX - startX + 1) * tileSize;
      height = (endY - startY + 1) * tileSize;

      // If dimensions are safe, stop.
      if (width <= maxDimension && height <= maxDimension) {
        break;
      }

      zoom--; // Zoom out
      if (zoom < 2) break; // Don't zoom out past World View
    }

    // ---------------------------------------------------------
    // 3. CREATE CANVAS
    // ---------------------------------------------------------
    img.Image fullCanvas = img.Image(width: width, height: height);

    // Fill with WHITE. If tiles fail, you get a white map instead of black.
    img.fill(fullCanvas, color: img.ColorRgb8(255, 255, 255));

    // ---------------------------------------------------------
    // 4. DOWNLOAD TILES (The "Polite" Loop)
    // ---------------------------------------------------------
    for (int x = startX; x <= endX; x++) {
      for (int y = startY; y <= endY; y++) {

        // DELAY: Wait 300ms to avoid "Access Blocked" from OSM
        await Future.delayed(const Duration(milliseconds: 300));

        try {
          final url = Uri.parse('https://tile.openstreetmap.org/$zoom/$x/$y.png');

          // HEADER: Identify as a valid project to avoid blocking
          final response = await http.get(url, headers: {
            'User-Agent': 'GeoVisionProject/1.0 (Education/Research)'
          });

          if (response.statusCode == 200) {
            final tile = img.decodePng(response.bodyBytes);
            if (tile != null) {
              int dstX = (x - startX) * tileSize;
              int dstY = (y - startY) * tileSize;
              img.compositeImage(fullCanvas, tile, dstX: dstX, dstY: dstY);
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print("❌ Network Error: $e");
          }
        }
      }
    }

    // ---------------------------------------------------------
    // 5. GENERATE & MERGE HEATMAP
    // ---------------------------------------------------------
    // Calculate Lat/Lng of the canvas edges
    double n = tile2lat(startY, zoom);
    double w = tile2lng(startX, zoom);
    double s = tile2lat(endY + 1, zoom);
    double e = tile2lng(endX + 1, zoom);

    final heatmapLayer = DartKDE.generateHeatmapOnMap(
      points: points,
      width: width,
      height: height,
      maxLat: n,
      minLat: s,
      minLng: w,
      maxLng: e,
    );

    // Merge using Alpha Blending (Transparency)
    img.compositeImage(fullCanvas, heatmapLayer, blend: img.BlendMode.alpha);

    // ---------------------------------------------------------
    // 6. CROP TO DATA (Remove excess tiles)
    // ---------------------------------------------------------
    var p1 = TileMath.latLngToPixel(dataMaxLat, dataMinLng, zoom);
    var p2 = TileMath.latLngToPixel(dataMinLat, dataMaxLng, zoom);

    double originX = startX * 256.0;
    double originY = startY * 256.0;

    int cropX = (p1.x - originX).toInt();
    int cropY = (p1.y - originY).toInt();
    int cropW = (p2.x - p1.x).toInt();
    int cropH = (p2.y - p1.y).toInt();

    // Safety clamps
    cropX = max(0, min(cropX, width - 1));
    cropY = max(0, min(cropY, height - 1));
    if (cropX + cropW > width) cropW = width - cropX;
    if (cropY + cropH > height) cropH = height - cropY;

    if (cropW > 0 && cropH > 0) {
      return img.copyCrop(fullCanvas, x: cropX, y: cropY, width: cropW, height: cropH);
    }

    return fullCanvas;
  }

  // ---------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------
  static double tile2lng(int x, int z) {
    return (x / pow(2, z) * 360.0) - 180;
  }

  static double tile2lat(int y, int z) {
    double n = pi - 2.0 * pi * y / pow(2, z);
    return 180.0 / pi * atan(0.5 * (exp(n) - exp(-n)));
  }
}