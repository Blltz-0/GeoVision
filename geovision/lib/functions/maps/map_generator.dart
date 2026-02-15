import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'dart_kde.dart';
import 'tile_math.dart';

class MapCompositor {
  static const int tileSize = 256;
  static const int maxDimension = 2500;

  static Future<img.Image?> generateFinalMap(List<Map<String, double>> points) async {
    if (points.isEmpty) return null;

    double minLat = points.map((e) => e['lat']!).reduce(min);
    double maxLat = points.map((e) => e['lat']!).reduce(max);
    double minLng = points.map((e) => e['lng']!).reduce(min);
    double maxLng = points.map((e) => e['lng']!).reduce(max);

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

    double latBuf = (maxLat - minLat) * 0.1;
    double lngBuf = (maxLng - minLng) * 0.1;
    double dMinLat = minLat - latBuf, dMaxLat = maxLat + latBuf;
    double dMinLng = minLng - lngBuf, dMaxLng = maxLng + lngBuf;

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

    img.Image fullCanvas = img.Image(width: width, height: height);
    img.fill(fullCanvas, color: img.ColorRgb8(240, 240, 240));

    // --- CACHE & DOWNLOAD LOGIC ---
    final cacheDir = await getTemporaryDirectory();
    final client = http.Client();
    try {
      for (int x = startX; x <= endX; x++) {
        for (int y = startY; y <= endY; y++) {
          final cachePath = '${cacheDir.path}/tile_cache/$zoom/$x/$y.png';
          final cacheFile = File(cachePath);
          img.Image? tile;

          if (await cacheFile.exists()) {
            tile = img.decodePng(await cacheFile.readAsBytes());
          } else {
            await Future.delayed(const Duration(milliseconds: 100)); // Rate limit
            final url = Uri.parse('https://tile.openstreetmap.org/$zoom/$x/$y.png');
            try {
              final response = await client.get(url, headers: {'User-Agent': 'GeoVision/1.0'});
              if (response.statusCode == 200) {
                tile = img.decodePng(response.bodyBytes);
                // Save to cache
                await cacheFile.create(recursive: true);
                await cacheFile.writeAsBytes(response.bodyBytes);
              }
            } catch (_) {}
          }

          if (tile != null) {
            img.compositeImage(fullCanvas, tile,
                dstX: (x - startX) * tileSize, dstY: (y - startY) * tileSize);
          }
        }
      }
    } finally {
      client.close();
    }

    final heatmapLayer = DartKDE.generateWeightedHeatmap(
      points: points,
      width: width,
      height: height,
      maxLat: tile2lat(startY, zoom),
      minLat: tile2lat(endY + 1, zoom),
      minLng: tile2lng(startX, zoom),
      maxLng: tile2lng(endX + 1, zoom),
    );
    img.compositeImage(fullCanvas, heatmapLayer, blend: img.BlendMode.alpha);

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