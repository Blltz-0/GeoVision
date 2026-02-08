import 'dart:math';

class LocationClusterer {
  /// Groups points that are within [maxDistanceKm] of each other.
  static List<List<Map<String, double>>> clusterPoints(
      List<Map<String, double>> allPoints,
      double maxDistanceKm
      ) {
    if (allPoints.isEmpty) return [];

    List<List<Map<String, double>>> clusters = [];
    // Work on a copy to avoid side effects
    List<Map<String, double>> remaining = List.from(allPoints);

    while (remaining.isNotEmpty) {
      var currentCluster = <Map<String, double>>[];
      var seed = remaining.removeAt(0);
      currentCluster.add(seed);

      // Using a standard for-loop back-to-front for safe removal
      for (int i = remaining.length - 1; i >= 0; i--) {
        var point = remaining[i];
        double dist = _haversine(
            seed['lat']!,
            seed['lng']!,
            point['lat']!,
            point['lng']!
        );

        if (dist <= maxDistanceKm) {
          currentCluster.add(point);
          remaining.removeAt(i);
        }
      }
      clusters.add(currentCluster);
    }
    return clusters;
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371; // Earth radius in km
    const p = pi / 180;
    var a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 2 * r * asin(sqrt(a));
  }
}