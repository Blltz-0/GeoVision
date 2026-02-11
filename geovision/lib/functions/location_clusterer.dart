import 'dart:math';

class LocationClusterer {
  /// Groups points that are within [maxDistanceKm] of each other.
  /// Uses a queue-based density approach to capture continuous regions.
  static List<List<Map<String, double>>> clusterPoints(
      List<Map<String, double>> allPoints,
      double maxDistanceKm,
      ) {
    if (allPoints.isEmpty) return [];

    List<List<Map<String, double>>> clusters = [];
    Set<int> visited = {};

    for (int i = 0; i < allPoints.length; i++) {
      if (visited.contains(i)) continue;

      List<Map<String, double>> currentCluster = [];
      List<int> queue = [i];
      visited.add(i);

      int qIdx = 0;
      while (qIdx < queue.length) {
        int currentIndex = queue[qIdx++];
        var currentPoint = allPoints[currentIndex];
        currentCluster.add(currentPoint);

        for (int j = 0; j < allPoints.length; j++) {
          if (visited.contains(j)) continue;

          double dist = _haversine(
            currentPoint['lat']!,
            currentPoint['lng']!,
            allPoints[j]['lat']!,
            allPoints[j]['lng']!,
          );

          if (dist <= maxDistanceKm) {
            visited.add(j);
            queue.add(j);
          }
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