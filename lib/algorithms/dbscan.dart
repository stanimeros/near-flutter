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

  Point? clusterPOIs(List<Point> points) {
    // Convert Points to List<List<double>> format
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    // Run DBSCAN
    List<List<int>> clusters = _dbscan.run(dataset);
    
    // If no clusters found, return null
    if (clusters.isEmpty) return null;

    // Get the largest cluster
    List<int> largestCluster = clusters.reduce((curr, next) => 
      curr.length > next.length ? curr : next
    );

    // If no points in largest cluster, return null
    if (largestCluster.isEmpty) return null;

    // Return a random point from the largest cluster
    largestCluster.shuffle();
    int randomIndex = largestCluster[0];
    
    return points[randomIndex];
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