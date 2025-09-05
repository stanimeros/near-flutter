import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:geolocator/geolocator.dart';

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

        // Initialize the spatial database
        debugPrint('Initializing spatial database...');
        await SpatialDb().openDbFileWithPath('detour_ratio_test.db');
        await SpatialDb().createSpatialTable(SpatialDb.pois);
        await SpatialDb().createCellsTable(SpatialDb.cells);

        for (final city in cities) {
            debugPrint('\nTesting city: ${city['name']}');
            
            for (final k in kValues) {
                debugPrint('\nTesting with k=$k');
                
                // Run 5 tests with different point combinations
                for (int i = 0; i < 5; i++) {
                    final userIdx = i;
                    final contactIdx = (i + 1) % (city['test_points'] as List).length;
                    
                    debugPrint('  Test ${i + 1}: Points ${userIdx + 1} and ${contactIdx + 1}');
                    try {
                        final result = await runDetourTest(city, k, userIdx, contactIdx);
                        results.add(result);
                        debugPrint('    Detour ratio: ${result['detour_ratio'].toStringAsFixed(2)}');
                    } catch (e) {
                        debugPrint('    Error: $e');
                    }
                }
            }
        }

        // Save results to JSON file
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
        final filename = 'test_results_$timestamp.json';
        final file = File(filename);
        await file.writeAsString(jsonEncode(results));
        debugPrint('\nResults saved to $filename');
        
        // Print summary statistics
        debugPrint('\n=== Summary Statistics ===');
        for (final city in cities) {
            debugPrint('\n${city['name']}:');
            for (final k in kValues) {
                final cityResults = results.where((r) => 
                    r['city_id'] == city['name'] && r['k_value'] == k
                ).toList();
                
                if (cityResults.isNotEmpty) {
                    final avgDetourRatio = cityResults
                        .map((r) => r['detour_ratio'] as double)
                        .reduce((a, b) => a + b) / cityResults.length;
                    
                    debugPrint('  k=$k: Average detour ratio = ${avgDetourRatio.toStringAsFixed(2)}');
                }
            }
        }
    }

    Future<Map<String, dynamic>> runDetourTest(
        Map<String, dynamic> city,
        int k,
        int userIdx,
        int contactIdx,
    ) async {
        // Setup test points
        final userPoint = city['test_points'][userIdx];
        final contactPoint = city['test_points'][contactIdx];
        
        // Create Point objects for spatial database
        final userSpatialPoint = Point(userPoint['lon'], userPoint['lat']);
        
        // Get KNN points for user
        final startTime = DateTime.now();
        final userKNNs = await SpatialDb().getKNNs(
            k,
            userSpatialPoint.lon,
            userSpatialPoint.lat,
            1000, // Start with 1km radius
            SpatialDb.pois,
            SpatialDb.cells,
        );
        final endTime = DateTime.now();
        
        if (userKNNs.isEmpty) {
            throw Exception('No KNN points found for user');
        }
        
        debugPrint('Found ${userKNNs.length} points (requested $k)');
        if (userKNNs.length < k) {
            debugPrint('Warning: Only found ${userKNNs.length} points (requested $k) - area may be too sparse');
        }
        
        // Select a random point from KNNs as the meeting point
        final random = Random();
        final meetingPoint = userKNNs[random.nextInt(userKNNs.length)];
        
        // Calculate detour ratio
        final detourRatio = calculateDetourRatio(
            userPoint['lat'], userPoint['lon'],
            contactPoint['lat'], contactPoint['lon'],
            meetingPoint.lat, meetingPoint.lon,
        );
        
        return {
            'timestamp': '${DateTime.now().toUtc().toIso8601String()}Z',
            'user_id': 'U${userIdx + 1}',
            'contact_ids': ['U${contactIdx + 1}'],
            'true_location': {'lat': userPoint['lat'], 'lon': userPoint['lon']},
            'generated_spoi': {'lat': meetingPoint.lat, 'lon': meetingPoint.lon},
            'candidate_spois': userKNNs.take(k).map((p) => {'lat': p.lat, 'lon': p.lon}).toList(),
            'k_value': k,
            'seed_info': '${DateTime.now().toUtc().toIso8601String()}Z',
            'system_information': {
                'network_latency_ms': endTime.difference(startTime).inMilliseconds.toDouble(),
                'cpu_usage_pct': 0.0,
                'battery_level_pct': 0.0,
            },
            'returned_contacts': [{
                'contact_id': 'U${contactIdx + 1}',
                'true_distance_m': Geolocator.distanceBetween(
                    userPoint['lat'], userPoint['lon'],
                    contactPoint['lat'], contactPoint['lon'],
                ),
                'near_distance_m': Geolocator.distanceBetween(
                    userPoint['lat'], userPoint['lon'],
                    meetingPoint.lat, meetingPoint.lon,
                ),
                'reported_rank': 1,
            }],
            'meeting_suggestion': {
                'city_id': city['name'],
                'cluster_id': 1,
                'meeting_point': {'lat': meetingPoint.lat, 'lon': meetingPoint.lon},
                'accepted': true,
                'detour_ratio': detourRatio,
            },
        };
    }
}
