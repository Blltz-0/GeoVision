import 'dart:math';

class LocationClusterer {
  /// Groups points that are within [maxDistanceKm] of each other.
  static List<List<Map<String, double>>> clusterPoints(
      List<Map<String, double>> allPoints,
      double maxDistanceKm
      ) {
    List<List<Map<String, double>>> clusters = [];
    List<Map<String, double>> remaining = List.from(allPoints);

    while (remaining.isNotEmpty) {
      // Start a new cluster with the first available point
      var currentCluster = <Map<String, double>>[];
      var seed = remaining.removeAt(0);
      currentCluster.add(seed);

      // Find all other points close to this seed
      // (Simple greedy clustering: if it's close to the seed, it joins the group)
      remaining.removeWhere((point) {
        double dist = _haversine(seed['lat']!, seed['lng']!, point['lat']!, point['lng']!);
        if (dist <= maxDistanceKm) {
          currentCluster.add(point);
          return true; // Remove from remaining
        }
        return false; // Keep in remaining
      });

      clusters.add(currentCluster);
    }
    return clusters;
  }

  // Calculate distance between two lat/lngs in km
  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371; // Earth radius in km
    var p = 0.017453292519943295;
    var a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 2 * r * asin(sqrt(a));
  }
}