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
            calculateDestinationPoint(centerLat, centerLon, 700, 30),
            calculateDestinationPoint(centerLat, centerLon, 300, 0),
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
  static void openVisualizationMap(BuildContext context, Map<String, dynamic> city, int k, int userIdx) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetourTestMapPage(
          city: city,
          k: k,
          userIdx: userIdx,
        ),
      ),
    );
  }

  // Method to run a single test with visualization option
  static Future<void> runSingleTestWithVisualization(BuildContext context, Map<String, dynamic> city, int k, int userIdx) async {
    debugPrint('Running single test: ${city['name']}, k=$k, User at point ${userIdx + 1}');
    
    try {
      final result = await DetourRatioTest().runDetourTest(city, k, userIdx, 0);
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
                  Text('User: Point ${userIdx + 1}'),
                  Text('Number of contacts: ${result['returned_contacts'].length}'),
                  SizedBox(height: 8),
                  Text(
                    'Detour Ratio: ${result['meeting_suggestion']['detour_ratio'].toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  Text('City: ${result['meeting_suggestion']['city_name']}'),
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
                    openVisualizationMap(context, city, k, userIdx);
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
                
                // Test each point as the user with all other points as contacts
                final testPoints = city['test_points'] as List;
                int testCount = 0;
                
                for (int userIdx = 0; userIdx < testPoints.length; userIdx++) {
                    testCount++;
                    debugPrint('Test $testCount/${testPoints.length}: User at point ${userIdx + 1} with all other points as contacts');
                    try {
                        final result = await runDetourTest(city, k, userIdx, testCount - 1);
                        results.add(result);
                        debugPrint('Detour ratio: ${result['meeting_suggestion']['detour_ratio'].toStringAsFixed(2)}');
                        debugPrint('Number of contacts: ${result['returned_contacts'].length}');
                    } catch (e) {
                        debugPrint('Error: $e');
                        // Still wait even if there's an error to prevent rapid retries
                        await Future.delayed(Duration(seconds: 2));
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
        
        // Print detailed test results
        debugPrint('\n=== Test Results ===');
        for (final city in cities) {
            debugPrint('\n${city['name']}:');
            for (final k in kValues) {
                debugPrint('\nk=$k:');
                final cityResults = results.where((r) => 
                    r['meeting_suggestion']['city_id'] == city['city_id'] && r['k_value'] == k
                ).toList();
                
                if (cityResults.isNotEmpty) {
                    for (final result in cityResults) {
                        debugPrint(
                            '  User ${result['user_id']}: '
                            'Detour ratio = ${result['meeting_suggestion']['detour_ratio'].toStringAsFixed(2)}, '
                            'Contacts = ${result['contact_ids'].join(', ')}'
                        );
                    }
                }
            }
        }
    }

    Future<Map<String, dynamic>> runDetourTest(
        Map<String, dynamic> city,
        int k,
        int userAIdx,
        int meetingAttempt,
    ) async {
        // Setup test point for User A
        final userAPoint = city['test_points'][userAIdx];
        
        // Create Point object for spatial database
        final userASpatialPoint = Point(userAPoint['lon'], userAPoint['lat']);
        
        // Generate SPOI for user A using two-step approach
        
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

        if (userAKNNs.isEmpty) {
            throw Exception('No KNN points found for user');
        }

        // Process all other test points as contacts
        final contacts = <Map<String, dynamic>>[];
        final spoiSeed = DateTime.now().millisecondsSinceEpoch;
        final spoiRandom = Random(spoiSeed);
        final userASPOI = userAKNNs[spoiRandom.nextInt(userAKNNs.length)];

        for (int contactIdx = 0; contactIdx < city['test_points'].length; contactIdx++) {
            if (contactIdx == userAIdx) continue; // Skip self

            final contactPoint = city['test_points'][contactIdx];
            final contactSpatialPoint = Point(contactPoint['lon'], contactPoint['lat']);

            // Generate SPOI for contact
            final nearestPointContact = await SpatialDb().getKNNs(
                1,
                contactSpatialPoint.lon,
                contactSpatialPoint.lat,
                50,
                SpatialDb.pois,
                SpatialDb.cells,
            );

            final contactKNNs = await SpatialDb().getKNNs(
                k,
                nearestPointContact.first.lon,
                nearestPointContact.first.lat,
                50,
                SpatialDb.pois,
                SpatialDb.cells,
            );

            if (contactKNNs.isEmpty) continue;

            final contactSPOI = contactKNNs[spoiRandom.nextInt(contactKNNs.length)];
            
            // Calculate distances
            final trueDistance = Geolocator.distanceBetween(
                userAPoint['lat'], userAPoint['lon'],
                contactPoint['lat'], contactPoint['lon'],
            );
            final nearDistance = Geolocator.distanceBetween(
                userASPOI.lat, userASPOI.lon,
                contactSPOI.lat, contactSPOI.lon,
            );

            contacts.add({
                'contact_id': 'U${contactIdx + 1}',
                'true_location': {'lat': contactPoint['lat'], 'lon': contactPoint['lon']},
                'generated_spoi': {'lat': contactSPOI.lat, 'lon': contactSPOI.lon},
                'true_distance_m': trueDistance,
                'near_distance_m': nearDistance,
            });
        }

        if (contacts.isEmpty) {
            throw Exception('No valid contacts found');
        }

        // Sort contacts by true distance and assign true_rank
        contacts.sort((a, b) => (a['true_distance_m'] as double).compareTo(b['true_distance_m'] as double));
        for (int i = 0; i < contacts.length; i++) {
            contacts[i]['true_rank'] = i + 1;
        }

        // Sort contacts by near distance and assign near_rank
        contacts.sort((a, b) => (a['near_distance_m'] as double).compareTo(b['near_distance_m'] as double));
        for (int i = 0; i < contacts.length; i++) {
            contacts[i]['near_rank'] = i + 1;
        }

        // Get clusters between the user's SPOI and the first contact's SPOI
        final firstContact = contacts.first;
        final clustersStartTime = DateTime.now();
        final clusters = await SpatialDb().getClustersBetweenTwoPoints(
            userASPOI,
            Point(
                firstContact['generated_spoi']['lon'],
                firstContact['generated_spoi']['lat'],
            ),
        );
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
        
        // Calculate detour ratio with first contact
        final detourRatio = calculateDetourRatio(
            userAPoint['lat'], userAPoint['lon'],
            firstContact['true_location']['lat'], firstContact['true_location']['lon'],
            meetingPoint.lat, meetingPoint.lon,
        );

        final data = await ResourceMonitor.getResourceUsage;
        final batteryLevel = (await Battery().batteryLevel).toDouble();
        
        return {
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'user_id': 'U${userAIdx + 1}',
            'contact_ids': contacts.map((c) => c['contact_id']).toList(),
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
            'returned_contacts': contacts,
            'meeting_suggestion': {
                'city_id': selectedCluster.cityId,
                'city_name': city['name'],
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