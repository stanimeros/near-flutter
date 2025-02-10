import 'package:simple_cluster/simple_cluster.dart';
import 'package:dart_jts/dart_jts.dart';
import 'dart:math';
class HierarchicalCluster {
  final int minClusters;
  final LINKAGE linkageType;
  late Hierarchical _hierarchical;

  HierarchicalCluster({
    this.minClusters = 2,
    this.linkageType = LINKAGE.AVERAGE,
  }) {
    _hierarchical = Hierarchical(
      minCluster: minClusters,
      linkage: linkageType,
    );
  }

  List<Point> filterPOIs(List<Point> points) {
    if (points.isEmpty) return [];

    // Pre-process: If too many points, use grid-based sampling
    if (points.length > 200) {
      points = _gridSample(points, 20); // 20x20 grid
    }

    // Convert Points to List<List<double>> format
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    // Run hierarchical clustering
    List<List<int>> clusters = _hierarchical.run(dataset);
    
    if (clusters.isEmpty) return [];

    List<int> selectedIndices = [];

    // Take points from each cluster
    for (var cluster in clusters) {
      if (cluster.isEmpty) continue;
      
      // For each cluster, take the medoid (most central point)
      int medoidIndex = _findMedoid(cluster, dataset);
      selectedIndices.add(medoidIndex);
      
      // If cluster is large, add a few more points
      if (cluster.length > 20) {
        cluster.shuffle();
        selectedIndices.addAll(
          cluster.where((i) => i != medoidIndex).take(4)
        );
      }
    }

    if (selectedIndices.isEmpty) return [];
    
    return selectedIndices.map((index) => points[index]).toList();
  }

  // Helper method to find the medoid of a cluster
  int _findMedoid(List<int> cluster, List<List<double>> dataset) {
    if (cluster.length == 1) return cluster[0];
    
    // Calculate centroid
    double sumX = 0, sumY = 0;
    for (var idx in cluster) {
      sumX += dataset[idx][0];
      sumY += dataset[idx][1];
    }
    double centerX = sumX / cluster.length;
    double centerY = sumY / cluster.length;
    
    // Find closest point to centroid
    return cluster.reduce((a, b) {
      double distA = _distance(dataset[a], [centerX, centerY]);
      double distB = _distance(dataset[b], [centerX, centerY]);
      return distA < distB ? a : b;
    });
  }

  // Helper method to sample points using a grid
  List<Point> _gridSample(List<Point> points, int gridSize) {
    // Find bounds
    double minX = points.map((p) => p.getX()).reduce((a, b) => a < b ? a : b);
    double maxX = points.map((p) => p.getX()).reduce((a, b) => a > b ? a : b);
    double minY = points.map((p) => p.getY()).reduce((a, b) => a < b ? a : b);
    double maxY = points.map((p) => p.getY()).reduce((a, b) => a > b ? a : b);
    
    // Create grid cells
    double cellWidth = (maxX - minX) / gridSize;
    double cellHeight = (maxY - minY) / gridSize;
    
    // Group points into grid cells
    Map<String, List<Point>> grid = {};
    for (var point in points) {
      int i = ((point.getX() - minX) / cellWidth).floor();
      int j = ((point.getY() - minY) / cellHeight).floor();
      String key = '$i,$j';
      grid.putIfAbsent(key, () => []).add(point);
    }
    
    // Take one point from each non-empty cell
    return grid.values.map((cell) {
      cell.shuffle();
      return cell.first;
    }).toList();
  }

  double _distance(List<double> a, List<double> b) {
    return sqrt(pow(a[0] - b[0], 2) + pow(a[1] - b[1], 2));
  }

  List<List<int>> getClusters(List<Point> points) {
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    return _hierarchical.run(dataset);
  }

  List<int> getNoise() {
    return _hierarchical.noise;
  }
}