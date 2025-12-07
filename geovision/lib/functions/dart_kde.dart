import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart'; // Used for Bounds

class DartKDE {

  // 1. THE MATH: Gaussian Kernel Function
  // This calculates "how much influence" a point has at a specific distance.
  static double _gaussianKernel(double distance, double bandwidth) {
    // Standard Gaussian Distribution formula
    return (1 / (sqrt(2 * pi) * bandwidth)) * exp(-(distance * distance) / (2 * bandwidth * bandwidth));
  }

  // 2. THE GENERATOR: Creates the Image + Bounds
  // This runs in a background isolate, so it must be static and independent.
  static Map<String, dynamic> generateHeatmap(List<Map<String, double>> points) {
    if (points.isEmpty) return {};

    // --- A. CALCULATE BOUNDS ---
    // Find the edges of your data
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

    if (maxLat - minLat < 0.01) {
      minLat -= 0.005;
      maxLat += 0.005;
    }
    if (maxLng - minLng < 0.01) {
      minLng -= 0.005;
      maxLng += 0.005;
    }

    // Add Padding (so points on the edge don't get cut off)
    // 0.002 degrees is approx 200 meters.
    const double padding = 0.002;
    minLat -= padding;
    maxLat += padding;
    minLng -= padding;
    maxLng += padding;

    // --- B. SETUP GRID ---
    // 300x300 is a good balance between Quality vs Speed.
    // Higher = Smoother but slower.
    const int width = 1000;
    const int height = 1000;

    // Create a 2D array to store density values
    List<List<double>> densityGrid = List.generate(height, (_) => List.filled(width, 0.0));
    double maxDensity = 0.0;

    // --- C. BANDWIDTH ---
    // Controls how "smooth" or "blobby" the map is.
    // 0.0005 is roughly 50m radius influence.
    const double bandwidth = 0.0005;

    // --- D. CALCULATE DENSITY (The Heavy Loop) ---
    for (int y = 0; y < height; y++) {
      // Map pixel Y to Latitude (Top is Max Lat, Bottom is Min Lat)
      double currentLat = maxLat - (y / height) * (maxLat - minLat);

      for (int x = 0; x < width; x++) {
        // Map pixel X to Longitude (Left is Min Lng, Right is Max Lng)
        double currentLng = minLng + (x / width) * (maxLng - minLng);

        double sumDensity = 0.0;

        // Check every data point's influence on this pixel
        for (var p in points) {
          double dLat = currentLat - p['lat']!;
          double dLng = currentLng - p['lng']!;
          // Euclidean distance (Simplified for speed)
          double dist = sqrt(dLat*dLat + dLng*dLng);

          // Optimization: Only compute if close enough (3 standard deviations)
          if (dist < bandwidth * 4) {
            sumDensity += _gaussianKernel(dist, bandwidth);
          }
        }

        densityGrid[y][x] = sumDensity;
        if (sumDensity > maxDensity) maxDensity = sumDensity;
      }
    }

    // --- E. DRAW IMAGE ---
    // Create the image buffer
    final image = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Normalize density 0.0 -> 1.0
        double normalized = maxDensity > 0 ? densityGrid[y][x] / maxDensity : 0;

        // --- COLOR MAP (Inferno Style) ---
        // 0.0 -> Transparent
        // 0.2 -> Blue
        // 0.5 -> Green/Yellow
        // 1.0 -> Red

        int r = 0, g = 0, b = 0, a = 0;

        if (normalized < 0.33) {
          // Too faint, make transparent
          a = 0;
        } else {
          // Manual Gradient Logic
          if (normalized < 0.33) {
            // Blue to Cyan
            double t = normalized / 0.33;
            r = 0;
            g = (t * 255).toInt();
            b = 255;
          } else if (normalized < 0.66) {
            // Cyan to Yellow
            double t = (normalized - 0.33) / 0.33;
            r = (t * 255).toInt();
            g = 255;
            b = (255 * (1-t)).toInt();
          } else {
            // Yellow to Red
            double t = (normalized - 0.66) / 0.34;
            r = 255;
            g = (255 * (1-t)).toInt();
            b = 0;
          }
          // Opacity logic: Faint areas are see-through
          a = (normalized * 255).clamp(0, 180).toInt();
        }

        image.setPixelRgba(x, y, r, g, b, a);
      }
    }

    // --- F. RETURN DATA ---
    // Return bytes for the image and the coordinates for where to place it
    return {
      "imageBytes": img.encodePng(image),
      "north": maxLat,
      "south": minLat,
      "east": maxLng,
      "west": minLng
    };
  }
}