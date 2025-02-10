import 'package:simple_cluster/simple_cluster.dart';
import 'package:dart_jts/dart_jts.dart';

class DBSCANCluster {
  final double epsilon;
  final int minPoints;
  late DBSCAN _dbscan;
  
  DBSCANCluster({
    this.epsilon = 3.0,
    this.minPoints = 2,
  }) {
    _dbscan = DBSCAN(
      epsilon: epsilon,
      minPoints: minPoints,
    );
  }

  List<Point> filterPOIs(List<Point> points) {
    if (points.isEmpty) return [];

    // Convert Points to List<List<double>> format
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    // Run DBSCAN
    List<List<int>> clusters = _dbscan.run(dataset);
    List<int> noise = _dbscan.noise;
    
    // If no clusters found, try to use noise points
    if (clusters.isEmpty && noise.isEmpty) return [];

    List<int> selectedIndices = [];

    // Process clusters
    if (clusters.isNotEmpty) {
      // Sort clusters by size (largest first)
      clusters.sort((a, b) => b.length.compareTo(a.length));

      // Take points from each cluster
      for (var cluster in clusters) {
        if (cluster.isEmpty) continue;
        
        // For larger clusters, take more points
        int pointsToTake = _getPointsToTake(cluster.length);
        cluster.shuffle();
        selectedIndices.addAll(cluster.take(pointsToTake));
      }
    }

    // Add some noise points if we don't have enough points
    if (selectedIndices.length < 50 && noise.isNotEmpty) {
      noise.shuffle();
      int remainingPoints = 50 - selectedIndices.length;
      int noisePointsToTake = noise.length > remainingPoints ? remainingPoints : noise.length;
      selectedIndices.addAll(noise.take(noisePointsToTake));
    }

    // If still not enough points, add more from largest clusters
    if (selectedIndices.length < 30 && clusters.isNotEmpty) {
      var largestCluster = clusters[0];
      largestCluster.shuffle();
      selectedIndices.addAll(
        largestCluster.where((i) => !selectedIndices.contains(i)).take(30 - selectedIndices.length)
      );
    }

    return selectedIndices.map((index) => points[index]).toList();
  }

  // Helper method to determine how many points to take based on cluster size
  int _getPointsToTake(int clusterSize) {
    if (clusterSize < 5) return 1;
    if (clusterSize < 10) return 2;
    if (clusterSize < 20) return 3;
    if (clusterSize < 50) return 5;
    return 8; // For very large clusters
  }

  List<List<int>> getClusters(List<Point> points) {
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    return _dbscan.run(dataset);
  }

  List<int> getNoise() {
    return _dbscan.noise;
  }
}