import 'dart:math';
import 'package:image/image.dart' as img;

class DartKDE {

  static double _gaussianKernel(double distance, double bandwidth) {
    return (1 / (sqrt(2 * pi) * bandwidth)) * exp(-(distance * distance) / (2 * bandwidth * bandwidth));
  }

  static img.Image generateHeatmapOnMap({
    required List<Map<String, double>> points,
    required int width,
    required int height,
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) {
    // 1. Setup Image (Transparent)
    final heatmapImage = img.Image(width: width, height: height, numChannels: 4);
    img.fill(heatmapImage, color: img.ColorRgba8(0, 0, 0, 0));

    // ✅ FIX 1: DYNAMIC BANDWIDTH
    // Instead of fixed 0.0005, we calculate it based on the map's latitude span.
    // "Span / 40" means a single point's glow will cover roughly 1/40th of the map height.
    double latSpan = maxLat - minLat;
    double bandwidth = latSpan / 40.0;

    // Safety clamps: Don't let it get microscopic or massive
    // 0.0001 is approx 10m, 0.5 is approx 50km
    bandwidth = bandwidth.clamp(0.0001, 0.5);

    print("   > Heatmap Logic: Dynamic Bandwidth set to $bandwidth for span $latSpan");

    // 2. Setup Grid
    List<List<double>> densityGrid = List.generate(height, (_) => List.filled(width, 0.0));
    double maxDensity = 0.0;

    // 3. Calculate Density
    for (int y = 0; y < height; y++) {
      double currentLat = maxLat - (y / height) * (maxLat - minLat);

      for (int x = 0; x < width; x++) {
        double currentLng = minLng + (x / width) * (maxLng - minLng);
        double sumDensity = 0.0;

        for (var p in points) {
          // Optimization: Skip points too far for this dynamic bandwidth
          if ((p['lat']! - currentLat).abs() > bandwidth * 4) continue;
          if ((p['lng']! - currentLng).abs() > bandwidth * 4) continue;

          double dLat = currentLat - p['lat']!;
          double dLng = currentLng - p['lng']!;
          double dist = sqrt(dLat*dLat + dLng*dLng);

          if (dist < bandwidth * 4) {
            sumDensity += _gaussianKernel(dist, bandwidth);
          }
        }
        densityGrid[y][x] = sumDensity;
        if (sumDensity > maxDensity) maxDensity = sumDensity;
      }
    }

    // 4. Paint Pixels
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double normalized = maxDensity > 0 ? densityGrid[y][x] / maxDensity : 0;

        if (normalized >= 0.05) {
          int r = 0, g = 0, b = 0;
          // Blue -> Green -> Red gradient
          if (normalized < 0.33) {
            double t = normalized / 0.33;
            r = 0; g = (t * 255).toInt(); b = 255;
          } else if (normalized < 0.66) {
            double t = (normalized - 0.33) / 0.33;
            r = (t * 255).toInt(); g = 255; b = (255 * (1-t)).toInt();
          } else {
            double t = (normalized - 0.66) / 0.34;
            r = 255; g = (255 * (1-t)).toInt(); b = 0;
          }
          int a = (normalized * 200 + 55).clamp(0, 200).toInt();
          heatmapImage.setPixel(x, y, img.ColorRgba8(r, g, b, a));
        }
      }
    }
    return heatmapImage;
  }
}