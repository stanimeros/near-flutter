import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:resource_monitor/resource_monitor.dart';
import 'package:share_plus/share_plus.dart';

//pick a random point close from cluster center go
//after spoi generaetion just pick 5 random clusters

class DetourRatioTest {
    // Detour Ratio Test Data
    static const Map<String, dynamic> thessaloniki = {
        "name": "Thessaloniki",
        "center": {"lat": 40.6401, "lon": 22.9444},
        "test_points": [
            {"lat": 40.6401, "lon": 22.9444},  // City center
            {"lat": 40.6772, "lon": 22.9114},  // Evosmos
            {"lat": 40.5764, "lon": 22.9583},  // Kalamaria
            {"lat": 40.6532, "lon": 22.9348},  // Aristotelous Square
            {"lat": 40.6263, "lon": 22.9532},  // White Tower
        ]
    };

    static const Map<String, dynamic> komotini = {
        "name": "Komotini",
        "center": {"lat": 41.1224, "lon": 25.4066},
        "test_points": [
            {"lat": 41.1224, "lon": 25.4066},  // City center
            {"lat": 41.1193, "lon": 25.4053},  // Central Square
            {"lat": 41.1172, "lon": 25.4133},  // Train Station
            {"lat": 41.1286, "lon": 25.4001},  // University Campus
            {"lat": 41.1156, "lon": 25.3989},  // West Komotini
        ]
    };

    static double calculateDetourRatio(
        double userLat, double userLon,
        double contactLat, double contactLon,
        double meetingLat, double meetingLon
    ) {
        final dUserMeeting = Geolocator.distanceBetween(userLat, userLon, meetingLat, meetingLon);
        final dContactMeeting = Geolocator.distanceBetween(contactLat, contactLon, meetingLat, meetingLon);
        final dUserContact = Geolocator.distanceBetween(userLat, userLon, contactLat, contactLon);
        
        if (dUserContact == 0) return 1.0;
        return (dUserMeeting + dContactMeeting) / dUserContact;
    }

    Future<void> runDetourRatioTest() async {
        debugPrint('Starting detour ratio tests...');
        
        final kValues = [5, 25, 100];
        final cities = [thessaloniki, komotini];
        final results = <Map<String, dynamic>>[];

        for (final city in cities) {
            debugPrint('\nTesting city: ${city['name']}');
            
            for (final k in kValues) {
                debugPrint('\nTesting with k=$k');
                
                // Test all combinations of test points (5×5=25 combinations, excluding same location = 20 combinations)
                final testPoints = city['test_points'] as List;
                int combinationCount = 0;
                final totalCombinations = testPoints.length * testPoints.length - testPoints.length; // 5×5 - 5 = 20
                
                for (int userAIdx = 0; userAIdx < testPoints.length; userAIdx++) {
                    for (int userBIdx = 0; userBIdx < testPoints.length; userBIdx++) {
                        // Skip if both users are at the same location
                        if (userAIdx == userBIdx) continue;
                        
                        combinationCount++;
                        debugPrint('Combination $combinationCount/$totalCombinations: User A (U1) at point ${userAIdx + 1}, User B (U2) at point ${userBIdx + 1}');
                        try {
                            final result = await runDetourTest(city, k, userAIdx, userBIdx, combinationCount - 1);
                            results.add(result);
                            debugPrint('Detour ratio: ${result['meeting_suggestion']['detour_ratio'].toStringAsFixed(2)}');
                        } catch (e) {
                            debugPrint('Error: $e');
                            // Still wait even if there's an error to prevent rapid retries
                            await Future.delayed(Duration(seconds: 2));
                        }
                    }
                }
                
                // Add extra delay between different k-values
                if (k != kValues.last) {
                    debugPrint('Completed k=$k tests');
                    await Future.delayed(Duration(seconds: 1));
                }
            }
            
            // Add delay between cities
            if (city != cities.last) {
                debugPrint('Completed ${city['name']} tests');
                await Future.delayed(Duration(seconds: 1));
            }
        }

        await shareResults(results);
        
        // Print summary statistics
        debugPrint('\n=== Summary Statistics ===');
        for (final city in cities) {
            debugPrint('\n${city['name']}:');
            for (final k in kValues) {
                final cityResults = results.where((r) => 
                    r['meeting_suggestion']['city_id'] == city['name'] && r['k_value'] == k
                ).toList();
                
                if (cityResults.isNotEmpty) {
                    final avgDetourRatio = cityResults
                        .map((r) => r['meeting_suggestion']['detour_ratio'] as double)
                        .reduce((a, b) => a + b) / cityResults.length;
                    
                    debugPrint('  k=$k: Average detour ratio = ${avgDetourRatio.toStringAsFixed(2)}');
                }
            }
        }
    }

    Future<Map<String, dynamic>> runDetourTest(
        Map<String, dynamic> city,
        int k,
        int userAIdx,
        int userBIdx,
        int meetingAttempt,
    ) async {
        // Setup test points for User A and User B
        final userAPoint = city['test_points'][userAIdx];
        final userBPoint = city['test_points'][userBIdx];
        
        // Create Point objects for spatial database
        final userASpatialPoint = Point(userAPoint['lon'], userAPoint['lat']);
        final userBSpatialPoint = Point(userBPoint['lon'], userBPoint['lat']);
        
        // Generate SPOIs for both users using two-step approach
        
        // Step 1: Get 1 nearest point for User A
        final nearestPointA = await SpatialDb().getKNNs(
            1,
            userASpatialPoint.lon,
            userASpatialPoint.lat,
            50,
            SpatialDb.pois,
            SpatialDb.cells,
        );
        
        // Step 2: Get k nearest points from User A's nearest point location
        final userAKNNs = await SpatialDb().getKNNs(
            k,
            nearestPointA.first.lon,
            nearestPointA.first.lat,
            50,
            SpatialDb.pois,
            SpatialDb.cells,
        );
        
        // Step 1: Get 1 nearest point for User B
        final nearestPointB = await SpatialDb().getKNNs(
            1,
            userBSpatialPoint.lon,
            userBSpatialPoint.lat,
            50,
            SpatialDb.pois,
            SpatialDb.cells,
        );
        
        // Step 2: Get k nearest points from User B's nearest point location
        final userBKNNs = await SpatialDb().getKNNs(
            k,
            nearestPointB.first.lon,
            nearestPointB.first.lat,
            50,
            SpatialDb.pois,
            SpatialDb.cells,
        );
        
        if (userAKNNs.isEmpty || userBKNNs.isEmpty) {
            throw Exception('No KNN points found for users');
        }
        
        // Select random SPOIs for both users
        final random = Random();
        final userASPOI = userAKNNs[random.nextInt(userAKNNs.length)];
        final userBSPOI = userBKNNs[random.nextInt(userBKNNs.length)];
        
        // Get clusters between the two SPOIs via API
        final clustersStartTime = DateTime.now();
        final clusters = await SpatialDb().getClustersBetweenTwoPoints(userASPOI, userBSPOI);
        final clustersEndTime = DateTime.now();
        
        if (clusters.isEmpty) {
            throw Exception('No clusters found between SPOIs');
        }
        
        // Choose a random cluster with timestamp seed
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final seededRandom = Random(timestamp);
        final selectedCluster = clusters[seededRandom.nextInt(clusters.length)];
        
        // Get the meeting point (first point in the cluster)
        final meetingPoint = selectedCluster.corePoint;
        
        // Calculate detour ratio: (d(A,Σ)+d(B,Σ)) / d(A,B)
        final detourRatio = calculateDetourRatio(
            userAPoint['lat'], userAPoint['lon'],
            userBPoint['lat'], userBPoint['lon'],
            meetingPoint.lat, meetingPoint.lon,
        );
        
        // Calculate distances
        final trueDistanceAB = Geolocator.distanceBetween(
            userAPoint['lat'], userAPoint['lon'],
            userBPoint['lat'], userBPoint['lon'],
        );
        final nearDistanceAB = Geolocator.distanceBetween(
            userASPOI.lat, userASPOI.lon,
            userBSPOI.lat, userBSPOI.lon,
        );

        final data = await ResourceMonitor.getResourceUsage;
        final batteryLevel = (await Battery().batteryLevel).toDouble();
        
        return {
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'user_id': 'U1',
            'contact_ids': ['U2'],
            'true_location': {'lat': userAPoint['lat'], 'lon': userAPoint['lon']},
            'generated_spoi': {'lat': userASPOI.lat, 'lon': userASPOI.lon},
            'candidate_spois': userAKNNs.map((p) => {'lat': p.lat, 'lon': p.lon}).toList(),
            'k_value': k,
            'seed_info': timestamp.toString(),
            'system_information': {
                'network_latency_ms': clustersEndTime.difference(clustersStartTime).inMilliseconds.toDouble(),
                'cpu_usage_pct': data.cpuInUseByApp,
                'battery_level_pct': batteryLevel,
                'memory_usage_bytes': data.memoryInUseByApp.toInt(),
            },
            'returned_contacts': [{
                'contact_id': 'U2',
                'true_distance_m': trueDistanceAB,
                'near_distance_m': nearDistanceAB,
                'reported_rank': 1,
            }],
            'meeting_suggestion': {
                'city_id': selectedCluster.city,
                'cluster_id': selectedCluster.id,
                'meeting_point': {'lat': meetingPoint.lat, 'lon': meetingPoint.lon},
                'accepted': true,
                'detour_ratio': detourRatio,
            },
        };
    }

  Future<void> shareResults(List<Map<String, dynamic>> results) async {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')[0];
    final filename = 'test_results_$timestamp.json';

    // Encode the list of results to JSON bytes
    final jsonBytes = utf8.encode(jsonEncode(results));

    // Prepare share params
    final params = ShareParams(
      files: [
        XFile.fromData(
          jsonBytes,
          mimeType: 'application/json',
          name: filename, // fallback name
        ),
      ],
      fileNameOverrides: [filename],
      text: 'Here are the test results',
    );

    // Trigger share sheet
    await SharePlus.instance.share(params);
  }
}