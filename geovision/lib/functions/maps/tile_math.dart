import 'dart:math';

class TileMath {
  static const int tileSize = 256;

  // Convert Lat/Lng to World Pixel Coordinates (at specific zoom)
  static Point<double> latLngToPixel(double lat, double lng, int zoom) {
    var siny = sin(lat * pi / 180);
    siny = min(max(siny, -0.9999), 0.9999);

    return Point(
      tileSize * (0.5 + lng / 360) * pow(2, zoom),
      tileSize * (0.5 - log((1 + siny) / (1 - siny)) / (4 * pi)) * pow(2, zoom),
    );
  }

  // Get the Tile X/Y index for a coordinate
  static Point<int> getTileIndex(double lat, double lng, int zoom) {
    final point = latLngToPixel(lat, lng, zoom);
    return Point(point.x.floor() ~/ tileSize, point.y.floor() ~/ tileSize);
  }
}