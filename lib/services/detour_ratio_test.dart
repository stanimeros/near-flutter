import 'dart:convert';
import 'dart:math';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:flutter_near/pages/detour_test_map_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:resource_monitor/resource_monitor.dart';
import 'package:share_plus/share_plus.dart';

//pick a random point close from cluster center go
//after spoi generaetion just pick 5 random clusters

class DetourRatioTest {
    // Helper function to calculate coordinates at a specific distance and bearing from a point
    static Map<String, double> calculateDestinationPoint(double lat, double lon, double distanceMeters, double bearingDegrees) {
        const double earthRadius = 6371000; // Earth's radius in meters
        
        final double latRad = lat * (3.14159265359 / 180);
        final double lonRad = lon * (3.14159265359 / 180);
        final double bearingRad = bearingDegrees * (3.14159265359 / 180);
        
        final double angularDistance = distanceMeters / earthRadius;
        
        final double newLatRad = math.asin(
            math.sin(latRad) * math.cos(angularDistance) +
            math.cos(latRad) * math.sin(angularDistance) * math.cos(bearingRad)
        );
        
        final double newLonRad = lonRad + math.atan2(
            math.sin(bearingRad) * math.sin(angularDistance) * math.cos(latRad),
            math.cos(angularDistance) - math.sin(latRad) * math.sin(newLatRad)
        );
        
        return {
            'lat': newLatRad * (180 / 3.14159265359),
            'lon': newLonRad * (180 / 3.14159265359)
        };
    }

    // Generate test points programmatically for consistent distances
    static List<Map<String, double>> generateTestPoints(double centerLat, double centerLon) {
        return [
            {"lat": centerLat, "lon": centerLon},  // Point 1: City center
            calculateDestinationPoint(centerLat, centerLon, 1000, -60),
        ];
    }

    // Detour Ratio Test Data
    static Map<String, dynamic> get thessaloniki => {
        "name": "ΘΕΣΣΑΛΟΝΙΚΗΣ",
        "city_id": "2335",
        "center": {"lat": 40.625163649564506, "lon": 22.959696666069682},
        "test_points": generateTestPoints(40.625163649564506, 22.959696666069682),
    };

    static Map<String, dynamic> get komotini => {
        "name": "ΚΟΜΟΤΗΝΗΣ", 
        "city_id": "2595",
        "center": {"lat": 41.11827569692981, "lon": 25.40374006496843},
        "test_points": generateTestPoints(41.11827569692981, 25.40374006496843),
    };

  // Method to open visualization map for a specific test
  static void openVisualizationMap(BuildContext context, Map<String, dynamic> city, int k, int userAIdx, int userBIdx) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetourTestMapPage(
          city: city,
          k: k,
          userAIdx: userAIdx,
          userBIdx: userBIdx,
        ),
      ),
    );
  }

  // Method to run a single test with visualization option
  static Future<void> runSingleTestWithVisualization(BuildContext context, Map<String, dynamic> city, int k, int userAIdx, int userBIdx) async {
    debugPrint('Running single test: ${city['name']}, k=$k, User A: ${userAIdx + 1}, User B: ${userBIdx + 1}');
    
    try {
      final result = await DetourRatioTest().runDetourTest(city, k, userAIdx, userBIdx, 0);
      debugPrint('Test completed. Detour ratio: ${result['meeting_suggestion']['detour_ratio'].toStringAsFixed(2)}');
      
      if (context.mounted) {
        // Show result dialog with option to visualize
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Test Result'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('City: ${city['name']}'),
                  Text('k: $k'),
                  Text('User A: Point ${userAIdx + 1}'),
                  Text('User B: Point ${userBIdx + 1}'),
                  SizedBox(height: 8),
                  Text(
                    'Detour Ratio: ${result['meeting_suggestion']['detour_ratio'].toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  Text('City ID: ${result['meeting_suggestion']['city_id']}'),
                  Text('Cluster ID: ${result['meeting_suggestion']['cluster_id']}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Close'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    openVisualizationMap(context, city, k, userAIdx, userBIdx);
                  },
                  child: Text('Visualize on Map'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      debugPrint('Test failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test failed: $e')),
        );
      }
    }
  }

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
                    r['meeting_suggestion']['city_id'] == city['city_id'] && r['k_value'] == k
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
        
        // Select random SPOIs for both users with SPOI seed
        final spoiSeed = DateTime.now().millisecondsSinceEpoch;
        final spoiRandom = Random(spoiSeed);
        final userASPOI = userAKNNs[spoiRandom.nextInt(userAKNNs.length)];
        final userBSPOI = userBKNNs[spoiRandom.nextInt(userBKNNs.length)];
        
        // Get clusters between the two SPOIs via API
        final clustersStartTime = DateTime.now();
        final clusters = await SpatialDb().getClustersBetweenTwoPoints(userASPOI, userBSPOI);
        final clustersEndTime = DateTime.now();
        
        if (clusters.isEmpty) {
            throw Exception('No clusters found between SPOIs');
        }
        
        // Choose a random cluster with meeting seed
        final meetingSeed = DateTime.now().millisecondsSinceEpoch;
        final meetingRandom = Random(meetingSeed);
        final selectedCluster = clusters[meetingRandom.nextInt(clusters.length)];
        
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
            'spoi_seed_info': spoiSeed.toString(),
            'meeting_seed_info': meetingSeed.toString(),
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
                'city_id': selectedCluster.cityId,
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