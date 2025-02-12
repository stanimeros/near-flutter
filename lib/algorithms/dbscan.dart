import 'package:dart_jts/dart_jts.dart';
import 'package:simple_cluster/simple_cluster.dart';

class DBSCANCluster {
  final double epsilon;
  final int minPoints;
  final int targetCount;
  late DBSCAN dbscan;
  
  DBSCANCluster({
    required this.epsilon,
    required this.minPoints,
    required this.targetCount,
  }) {
    dbscan = DBSCAN(
      epsilon: epsilon,
      minPoints: minPoints,
    );
  }

  List<Point> filterPOIs(List<Point> points) {
    if (points.isEmpty) return [];
    if (points.length <= targetCount) return points;

    // Convert Points to List<List<double>> format
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    // Run DBSCAN
    List<List<int>> clusters = dbscan.run(dataset);
    List<int> noise = dbscan.noise;
    
    // Collect all points (from clusters and noise)
    List<int> allIndices = [...noise];
    for (var cluster in clusters) {
      allIndices.addAll(cluster);
    }

    // Shuffle and take exactly targetCount points
    allIndices.shuffle();
    return allIndices.take(targetCount)
      .map((i) => points[i])
      .toList();
  }

  List<List<int>> getClusters(List<Point> points) {
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    return dbscan.run(dataset);
  }
}