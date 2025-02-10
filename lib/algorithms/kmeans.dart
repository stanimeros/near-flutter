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

    List<int> selectedIndices = [];

    // Take points from each cluster
    for (var cluster in clusters) {
      if (cluster.instances.isEmpty) continue;
      
      // Shuffle cluster points
      cluster.instances.shuffle();
      
      // Take up to 10 points from each cluster
      int pointsToTake = cluster.instances.length > 10 ? 10 : cluster.instances.length;
      selectedIndices.addAll(
        cluster.instances.take(pointsToTake).map((instance) => 
          instances.indexOf(instance)
        )
      );
    }

    // If no points selected, return empty list
    if (selectedIndices.isEmpty) return [];

    // Convert back to Points
    return selectedIndices.map((index) => points[index]).toList();
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

    List<int> selectedIndices = [];

    // Take points from each cluster
    for (var i = 0; i < clusters.clusterPoints.length; i++) {
      var clusterPoints = clusters.clusterPoints[i];
      if (clusterPoints.isEmpty) continue;
      
      // Shuffle cluster points
      clusterPoints.shuffle();
      
      // Take up to 10 points from each cluster
      int pointsToTake = clusterPoints.length > 10 ? 10 : clusterPoints.length;
      
      // Find indices of selected points in original dataset
      for (var point in clusterPoints.take(pointsToTake)) {
        int index = dataset.indexWhere((p) => 
          p[0] == point[0] && p[1] == point[1]
        );
        if (index != -1) {
          selectedIndices.add(index);
        }
      }
    }

    // If no points selected, return empty list
    if (selectedIndices.isEmpty) return [];
    
    // Convert back to Points
    return selectedIndices.map((index) => points[index]).toList();
  }
}
