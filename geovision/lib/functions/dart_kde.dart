import 'dart:math';
import 'package:image/image.dart' as img;

class DartKDE {
  static double _gaussianKernel(double distance, double bandwidth) {
    return (1 / (sqrt(2 * pi) * bandwidth)) *
        exp(-(distance * distance) / (2 * bandwidth * bandwidth));
  }

  /// Helper for perceptually smooth color transitions
  static img.ColorRgba8 _getSmoothColor(double t) {
    // Gradient: Deep Purple -> Red -> Orange -> Pale Yellow
    final colors = [
      [40, 0, 80],     // 0.0: Deep Purple
      [180, 0, 50],    // 0.25: Red
      [255, 100, 0],   // 0.5: Orange
      [255, 200, 0],   // 0.75: Amber
      [255, 255, 180], // 1.0: Hot Yellow
    ];

    // Map normalized value (0-1) to color indices
    double scaledT = t * (colors.length - 1);
    int index = scaledT.floor();
    double fraction = scaledT - index;

    // Boundary safety
    if (index >= colors.length - 1) return img.ColorRgba8(255, 255, 180, 200);

    var c1 = colors[index];
    var c2 = colors[index + 1];

    int r = (c1[0] + (c2[0] - c1[0]) * fraction).toInt();
    int g = (c1[1] + (c2[1] - c1[1]) * fraction).toInt();
    int b = (c1[2] + (c2[2] - c1[2]) * fraction).toInt();

    // Smooth alpha transition: starts at 50 transparency, ends at 210
    int a = (t * 160 + 50).toInt().clamp(0, 210);

    return img.ColorRgba8(r, g, b, a);
  }

  static img.Image generateWeightedHeatmap({
    required List<Map<String, double>> points,
    required int width,
    required int height,
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) {
    final heatmapImage = img.Image(width: width, height: height, numChannels: 4);
    img.fill(heatmapImage, color: img.ColorRgba8(0, 0, 0, 0));

    double latSpan = maxLat - minLat;
    double lngSpan = maxLng - minLng;
    double bandwidth = (latSpan / 40.0).clamp(0.0001, 0.5);

    List<List<double>> densityGrid = List.generate(height, (_) => List.filled(width, 0.0));
    double maxDensity = 0.0;

    for (var p in points) {
      double pLat = p['lat']!;
      double pLng = p['lng']!;
      double pWeight = p['weight'] ?? 1.0;

      int centerX = (((pLng - minLng) / lngSpan) * width).toInt();
      int centerY = (((maxLat - pLat) / latSpan) * height).toInt();
      int pixelRadius = ((bandwidth * 4 / latSpan) * height).toInt();

      for (int y = (centerY - pixelRadius).clamp(0, height - 1);
      y <= (centerY + pixelRadius).clamp(0, height - 1); y++) {
        double currentLat = maxLat - (y / height) * latSpan;
        for (int x = (centerX - pixelRadius).clamp(0, width - 1);
        x <= (centerX + pixelRadius).clamp(0, width - 1); x++) {
          double currentLng = minLng + (x / width) * lngSpan;

          double dLat = currentLat - pLat;
          double dLng = currentLng - pLng;
          double dist = sqrt(dLat * dLat + dLng * dLng);

          if (dist < bandwidth * 4) {
            densityGrid[y][x] += _gaussianKernel(dist, bandwidth) * pWeight;
            if (densityGrid[y][x] > maxDensity) maxDensity = densityGrid[y][x];
          }
        }
      }
    }

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double normalized = maxDensity > 0 ? densityGrid[y][x] / maxDensity : 0;
        // Ignore extremely low density for a clean map
        if (normalized >= 0.05) {
          heatmapImage.setPixel(x, y, _getSmoothColor(normalized));
        }
      }
    }
    return heatmapImage;
  }
}