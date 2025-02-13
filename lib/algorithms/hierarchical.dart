import 'package:simple_cluster/simple_cluster.dart';
import 'package:dart_jts/dart_jts.dart';

class HierarchicalCluster {
  final int minCluster;
  final LINKAGE linkageType;

  HierarchicalCluster({
    required this.minCluster,
    this.linkageType = LINKAGE.AVERAGE,
  });

  List<Point> filterPOIs(List<Point> points) {
    if (points.isEmpty) return [];

    // Convert Points to List<List<double>> format
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    // Run hierarchical clustering
    Hierarchical hierarchical = Hierarchical(
      minCluster: minCluster,
      linkage: linkageType,
    );
    List<List<int>> clusters = hierarchical.run(dataset);
    
    // Take one point from each cluster
    return clusters
        .where((cluster) => cluster.isNotEmpty)
        .map((cluster) => points[cluster[0]])
        .toList();
  }
}