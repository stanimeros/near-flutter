import 'package:dart_hydrologis_db/dart_hydrologis_db.dart';
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

    final List<int> kValues = [5, 25, 100];

    final List<BoundingBox> bboxes = [
        BoundingBox(22.90087984, 23.01946016, 40.58004055, 40.67004145), // 5km
        BoundingBox(22.6637192, 23.2566208, 40.40003875, 40.85004325), // 25km
        BoundingBox(21.77436679, 24.14597321, 39.725032, 41.52505), // 100km
    ];

    final List<String> poisAssets = [
        'assets/points/5km.txt',
        'assets/points/25km.txt',
        'assets/points/100km.txt',
    ];

    final List<TableName> poisTables = [
        TableName("pois_5", schemaSupported: false),
        TableName("pois_25", schemaSupported: false),
        TableName("pois_100", schemaSupported: false),
    ];

    final List<TableName> cellsTables = [
        TableName("cells_pois_5", schemaSupported: false),
        TableName("cells_pois_25", schemaSupported: false),
        TableName("cells_pois_100", schemaSupported: false),
    ];

    static const int numRuns = 5; // Number of times to run each experiment
        
    Future<void> runAllScenarios() async {
        // First download all cells
        for (int i = 0; i < poisTables.length; i++) {
            await SpatialDb().createSpatialTable(poisTables[i]);
            await SpatialDb().createCellsTable(cellsTables[i]);
            await SpatialDb().emptyTable(poisTables[i]);
            await SpatialDb().emptyTable(cellsTables[i]);
            await SpatialDb().importPointsFromAsset(poisAssets[i], poisTables[i]);
            
        }

        // 1. Fixed k=25 with varying dataset sizes
        for (int i = 0; i < poisTables.length; i++) {
            await runExperiment(kValues[1], poisTables[i], cellsTables[i]);
        }

        // 2. Fixed dataset size (25km) with varying k
        for (var k in kValues) {
            await runExperiment(k, poisTables[1], cellsTables[1]);
        }
    }

    Future<void> runExperiment(int k, TableName poisTable, TableName cellsTable) async {
        List<int> times = [];
        
        for (int run = 0; run < numRuns; run++) {
            int startTime = DateTime.now().millisecondsSinceEpoch;
            
            // Run the specific method implementation
            for (Point point in points) {
              await SpatialDb().getRandomKNN(
                k,
                point.lon,
                point.lat,
                50,
                poisTable,
                cellsTable
              );
            }
            
            int endTime = DateTime.now().millisecondsSinceEpoch;
            times.add(endTime - startTime);
        }
        
        // Calculate and store average time
        double avgTime = times.reduce((a, b) => a + b) / times.length;
        debugPrint("Dataset: ${poisTable.fixedName}, k: $k, Avg Time: ${avgTime.toStringAsFixed(2)} ms");
    }
}
