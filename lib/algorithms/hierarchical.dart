import 'package:simple_cluster/simple_cluster.dart';
import 'package:dart_jts/dart_jts.dart';

class HierarchicalCluster {
  final int minClusters;
  final LINKAGE linkageType;

  HierarchicalCluster({
    required this.minClusters,
    this.linkageType = LINKAGE.AVERAGE,
  });

  List<Point> filterPOIs(List<Point> points) {
    if (points.isEmpty) return [];
    if (points.length <= minClusters) return points;

    // Convert Points to List<List<double>> format
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    // Run hierarchical clustering
    Hierarchical hierarchical = Hierarchical(
      minCluster: minClusters,
      linkage: linkageType,
    );
    List<List<int>> clusters = hierarchical.run(dataset);
    
    // Collect all points from clusters
    List<int> allIndices = [];
    for (var cluster in clusters) {
      if (cluster.isNotEmpty) {
        allIndices.addAll(cluster);
      }
    }

    // Shuffle and take points
    allIndices.shuffle();
    return allIndices.take(minClusters)
      .map((i) => points[i])
      .toList();
  }
}