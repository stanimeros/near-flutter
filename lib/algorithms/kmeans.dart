import 'package:k_means_cluster/k_means_cluster.dart' as kmeans1;
import 'package:kmeans/kmeans.dart' as kmeans2;
import 'package:dart_jts/dart_jts.dart';

class KMeansCluster1 {
  final int k;

  KMeansCluster1({
    required this.k,
  });

  Point? clusterPOIs(List<Point> points) {
    if (points.isEmpty) return null;

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

    // Return a random point from the largest cluster
    if (largestCluster.instances.isEmpty) return null;
    
    largestCluster.instances.shuffle();
    List<num> randomLocation = largestCluster.instances.first.location;
    
    return Point(Coordinate(randomLocation[0].toDouble(), randomLocation[1].toDouble()), PrecisionModel(), 4326);
  }
}

class KMeansCluster2 {
  final int k;

  KMeansCluster2({
    required this.k,
  });

  Point? clusterPOIs(List<Point> points) {
    if (points.isEmpty) return null;

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

    // If no points in largest cluster, return null
    if (maxSize == 0) return null;

    // Return a random point from the largest cluster
    final clusterPoints = clusters.clusterPoints[largestClusterIndex];
    clusterPoints.shuffle();
    List<double> randomPoint = clusterPoints.first;
    
    return Point(Coordinate(randomPoint[0], randomPoint[1]), PrecisionModel(), 4326);
  }
}
