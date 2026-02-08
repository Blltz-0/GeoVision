import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'dart_kde.dart';
import 'tile_math.dart';

class MapCompositor {
  static const int tileSize = 256;
  static const int maxDimension = 2500;

  static Future<img.Image?> generateFinalMap(List<Map<String, double>> points) async {
    if (points.isEmpty) return null;

    // 1. Determine Data Bounds
    double minLat = points.map((e) => e['lat']!).reduce(min);
    double maxLat = points.map((e) => e['lat']!).reduce(max);
    double minLng = points.map((e) => e['lng']!).reduce(min);
    double maxLng = points.map((e) => e['lng']!).reduce(max);

    // Enforce minimum spread for single-point projects
    const double minSpread = 0.005;
    if ((maxLat - minLat) < minSpread) {
      double center = (maxLat + minLat) / 2;
      minLat = center - (minSpread / 2);
      maxLat = center + (minSpread / 2);
    }
    if ((maxLng - minLng) < minSpread) {
      double center = (maxLng + minLng) / 2;
      minLng = center - (minSpread / 2);
      maxLng = center + (minSpread / 2);
    }

    // Aesthetic Buffer (10%)
    double latBuf = (maxLat - minLat) * 0.1;
    double lngBuf = (maxLng - minLng) * 0.1;
    double dMinLat = minLat - latBuf, dMaxLat = maxLat + latBuf;
    double dMinLng = minLng - lngBuf, dMaxLng = maxLng + lngBuf;

    // 2. Calculate Zoom Level
    int zoom = 17;
    int width = 0, height = 0;
    int startX = 0, endX = 0, startY = 0, endY = 0;

    while (zoom > 2) {
      var tl = TileMath.getTileIndex(dMaxLat, dMinLng, zoom);
      var br = TileMath.getTileIndex(dMinLat, dMaxLng, zoom);
      startX = tl.x; endX = br.x;
      startY = tl.y; endY = br.y;

      width = (endX - startX + 1) * tileSize;
      height = (endY - startY + 1) * tileSize;

      if (width <= maxDimension && height <= maxDimension) break;
      zoom--;
    }

    // 3. Create Canvas
    img.Image fullCanvas = img.Image(width: width, height: height);
    img.fill(fullCanvas, color: img.ColorRgb8(240, 240, 240)); // Light grey background

    // 4. Download Tiles with Retry
    final client = http.Client();
    try {
      for (int x = startX; x <= endX; x++) {
        for (int y = startY; y <= endY; y++) {
          await Future.delayed(const Duration(milliseconds: 250)); // Throttling

          final url = Uri.parse('https://tile.openstreetmap.org/$zoom/$x/$y.png');
          img.Image? tile;

          // Simple Retry Logic
          for (int attempt = 0; attempt < 2; attempt++) {
            try {
              final response = await client.get(url, headers: {
                'User-Agent': 'GeoVisionProject/1.0'
              }).timeout(const Duration(seconds: 5));

              if (response.statusCode == 200) {
                tile = img.decodePng(response.bodyBytes);
                break;
              }
            } catch (_) {}
          }

          if (tile != null) {
            img.compositeImage(
                fullCanvas,
                tile,
                dstX: (x - startX) * tileSize,
                dstY: (y - startY) * tileSize
            );
          }
        }
      }
    } finally {
      client.close();
    }

    // 5. Heatmap Layer
    final heatmapLayer = DartKDE.generateHeatmapOnMap(
      points: points,
      width: width,
      height: height,
      maxLat: tile2lat(startY, zoom),
      minLat: tile2lat(endY + 1, zoom),
      minLng: tile2lng(startX, zoom),
      maxLng: tile2lng(endX + 1, zoom),
    );
    img.compositeImage(fullCanvas, heatmapLayer, blend: img.BlendMode.alpha);

    // 6. Final Crop
    var p1 = TileMath.latLngToPixel(dMaxLat, dMinLng, zoom);
    var p2 = TileMath.latLngToPixel(dMinLat, dMaxLng, zoom);
    double oX = startX * 256.0;
    double oY = startY * 256.0;

    int cX = max(0, (p1.x - oX).toInt());
    int cY = max(0, (p1.y - oY).toInt());
    int cW = min(width - cX, (p2.x - p1.x).toInt());
    int cH = min(height - cY, (p2.y - p1.y).toInt());

    return (cW > 0 && cH > 0)
        ? img.copyCrop(fullCanvas, x: cX, y: cY, width: cW, height: cH)
        : fullCanvas;
  }

  static double tile2lng(int x, int z) => (x / pow(2, z) * 360.0) - 180;
  static double tile2lat(int y, int z) {
    double n = pi - 2.0 * pi * y / pow(2, z);
    return 180.0 / pi * atan(0.5 * (exp(n) - exp(-n)));
  }
}