import 'package:k_means_cluster/k_means_cluster.dart' as kmeans1;
import 'package:kmeans/kmeans.dart' as kmeans2;
import 'package:dart_jts/dart_jts.dart';

class KMeansCluster1 {
  final int k;

  KMeansCluster1({
    required this.k,
  });

  List<Point> filterPOIs(List<Point> points) {
    if (points.isEmpty) return [];
    if (points.length <= k) return points;

    // Convert Points to List<List<double>> format
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    // Create and run k-means
    List<kmeans1.Instance> instances = dataset.map((coords) => 
      kmeans1.Instance(location: coords, id: coords.toString())
    ).toList();
    
    List<kmeans1.Cluster> clusters = kmeans1.initialClusters(k, instances);
    kmeans1.kMeans(clusters: clusters, instances: instances);

    // Take one point from each cluster
    List<Point> selectedPoints = [];
    for (var cluster in clusters) {
      if (cluster.instances.isEmpty) continue;
      
      // Take a random point from the cluster
      var instance = cluster.instances[0];
      selectedPoints.add(points[instances.indexOf(instance)]);
    }

    return selectedPoints;
  }
}

class KMeansCluster2 {
  final int k;

  KMeansCluster2({
    required this.k,
  });

  List<Point> filterPOIs(List<Point> points) {
    if (points.isEmpty) return [];
    if (points.length <= k) return points;

    // Convert Points to List<List<double>> format
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    // Run k-means
    final kmeans = kmeans2.KMeans(dataset);
    final clusters = kmeans.bestFit(minK: k, maxK: k);

    // Take one point from each cluster
    List<Point> selectedPoints = [];
    for (var clusterPoints in clusters.clusterPoints) {
      if (clusterPoints.isEmpty) continue;
      
      // Find the original point
      var point = clusterPoints[0];
      int index = dataset.indexWhere((p) => 
        p[0] == point[0] && p[1] == point[1]
      );
      if (index != -1) {
        selectedPoints.add(points[index]);
      }
    }

    return selectedPoints;
  }
}
