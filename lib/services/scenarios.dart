import 'package:flutter/foundation.dart';
import 'package:flutter_near/services/spatial_db.dart';

class Scenarios {
    final List<Point> points = [
        Point(22.9346, 40.6396),
        Point(22.9453, 40.6431),
        Point(22.9575, 40.6392),
        Point(22.9703, 40.6207),
        Point(22.9592, 40.6078),
    ];

    // Dataset configurations
    final List<int> datasetSizes = [5, 25, 100]; // kilometers
    final List<int> kValues = [5, 25, 100];      // number of nearest neighbors

    static const int numRuns = 5; // Number of times to run each experiment

    void runAllScenarios() {
        // 1. Fixed k=25 with varying dataset sizes
        for (int datasetSize in datasetSizes) {
            runExperiment(datasetSize, 25);
        }

        // 2. Fixed dataset size (25km) with varying k
        for (int k in kValues) {
            runExperiment(25, k);
        }
    }

    Future<void> runExperiment(int datasetSize, int k) async {
        List<int> times = [];
        
        for (int run = 0; run < numRuns; run++) {
            int startTime = DateTime.now().millisecondsSinceEpoch;
            
            // Run the specific method implementation
            for (Point point in points) {
              await SpatialDb().getRandomKNN(
                k,
                point.lon,
                point.lat,
                50
              );
            }
            
            int endTime = DateTime.now().millisecondsSinceEpoch;
            times.add(endTime - startTime);
        }
        
        // Calculate and store average time
        double avgTime = times.reduce((a, b) => a + b) / times.length;
        debugPrint("Dataset: $datasetSize km, k: $k, Avg Time: ${avgTime.toStringAsFixed(2)} ms");
    }
}
