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

    // Convert Points to List<List<double>> format
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    // Create Instance objects
    List<kmeans1.Instance> instances = dataset.map((coords) {
      return kmeans1.Instance(
        location: coords,
        id: coords.toString(),
      );
    }).toList();

    // Initialize clusters
    List<kmeans1.Cluster> clusters = kmeans1.initialClusters(k, instances);
    
    // Run k-means
    kmeans1.kMeans(clusters: clusters, instances: instances);

    // Get the largest cluster
    kmeans1.Cluster largestCluster = clusters.reduce((curr, next) => 
      curr.instances.length > next.instances.length ? curr : next
    );

    // If no points in largest cluster, return empty list
    if (largestCluster.instances.isEmpty) return [];

    // Shuffle and take up to 50 points from the largest cluster
    largestCluster.instances.shuffle();
    List<kmeans1.Instance> selectedInstances = largestCluster.instances.take(50).toList();

    // Convert back to Points
    return selectedInstances.map((instance) {
      List<num> location = instance.location;
      return Point(
        Coordinate(location[0].toDouble(), location[1].toDouble()),
        PrecisionModel(),
        4326
      );
    }).toList();
  }
}

class KMeansCluster2 {
  final int k;

  KMeansCluster2({
    required this.k,
  });

  List<Point> filterPOIs(List<Point> points) {
    if (points.isEmpty) return [];

    // Convert Points to List<List<double>> format
    List<List<double>> dataset = points.map((point) => [
      point.getX(),
      point.getY()
    ]).toList();

    // Create KMeans instance
    final kmeans = kmeans2.KMeans(dataset);
    
    // Run clustering
    final clusters = kmeans.bestFit(
      minK: k,
      maxK: k,
    );

    // Find the largest cluster
    int largestClusterIndex = 0;
    int maxSize = 0;
    
    for (int i = 0; i < clusters.clusterPoints.length; i++) {
      if (clusters.clusterPoints[i].length > maxSize) {
        maxSize = clusters.clusterPoints[i].length;
        largestClusterIndex = i;
      }
    }

    // If no points in largest cluster, return empty list
    if (maxSize == 0) return [];

    // Get points from the largest cluster
    final clusterPoints = clusters.clusterPoints[largestClusterIndex];
    
    // Shuffle and take up to 50 points
    clusterPoints.shuffle();
    List<List<double>> selectedPoints = clusterPoints.take(50).toList();
    
    // Convert back to Points
    return selectedPoints.map((coords) => 
      Point(
        Coordinate(coords[0], coords[1]),
        PrecisionModel(),
        4326
      )
    ).toList();
  }
}
