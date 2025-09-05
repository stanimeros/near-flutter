// Detour Ratio Test
// 
// This test calculates detour ratios for meeting point suggestions using the spatial database.
// It tests different k-values (5, 25, 100) across two cities (Thessaloniki and Komotini).
// 
// To run this test and generate JSON results:
// flutter test test/detour_ratio_test.dart
//
// The test will create a JSON file with timestamp: test_results_YYYY-MM-DDTHH-MM-SS.json
// containing detailed results for each test iteration including detour ratios, distances,
// and meeting point suggestions.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:geolocator/geolocator.dart';

// Test data for Thessaloniki and Komotini
const Map<String, dynamic> thessaloniki = {
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

const Map<String, dynamic> komotini = {
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

class TestResult {
  final String timestamp;
  final String userId;
  final List<String> contactIds;
  final Map<String, double> trueLocation;
  final Map<String, double> generatedSpoi;
  final List<Map<String, double>> candidateSpois;
  final int kValue;
  final String seedInfo;
  final Map<String, double> systemInformation;
  final List<Map<String, dynamic>> returnedContacts;
  final Map<String, dynamic> meetingSuggestion;

  TestResult({
    required this.timestamp,
    required this.userId,
    required this.contactIds,
    required this.trueLocation,
    required this.generatedSpoi,
    required this.candidateSpois,
    required this.kValue,
    required this.seedInfo,
    required this.systemInformation,
    required this.returnedContacts,
    required this.meetingSuggestion,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'user_id': userId,
      'contact_ids': contactIds,
      'true_location': trueLocation,
      'generated_spoi': generatedSpoi,
      'candidate_spois': candidateSpois,
      'k_value': kValue,
      'seed_info': seedInfo,
      'system_information': systemInformation,
      'returned_contacts': returnedContacts,
      'meeting_suggestion': meetingSuggestion,
    };
  }
}

class DetourRatioTest {
  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  static double calculateDetourRatio(
    double userLat, double userLon,
    double contactLat, double contactLon,
    double meetingLat, double meetingLon
  ) {
    final dUserMeeting = calculateDistance(userLat, userLon, meetingLat, meetingLon);
    final dContactMeeting = calculateDistance(contactLat, contactLon, meetingLat, meetingLon);
    final dUserContact = calculateDistance(userLat, userLon, contactLat, contactLon);
    
    if (dUserContact == 0) return 1.0;
    return (dUserMeeting + dContactMeeting) / dUserContact;
  }

  static Future<TestResult> runTest(
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
    
    // Get KNN points for user (like in friends_page.dart)
    final startTime = DateTime.now();
    final userKNNs = await SpatialDb().getKNNs(
      k,
      userSpatialPoint.lon,
      userSpatialPoint.lat,
      50, // buffer meters
      SpatialDb.pois,
      SpatialDb.cells,
    );
    final endTime = DateTime.now();
    
    if (userKNNs.isEmpty) {
      throw Exception('No KNN points found for user');
    }
    
    // Select a random point from KNNs as the meeting point (like in friends_page.dart)
    final random = Random();
    final meetingPoint = userKNNs[random.nextInt(userKNNs.length)];
    
    // Calculate detour ratio
    final detourRatio = calculateDetourRatio(
      userPoint['lat'], userPoint['lon'],
      contactPoint['lat'], contactPoint['lon'],
      meetingPoint.lat, meetingPoint.lon,
    );
    
    // Create test result
    return TestResult(
      timestamp: '${DateTime.now().toUtc().toIso8601String()}Z',
      userId: 'U${userIdx + 1}',
      contactIds: ['U${contactIdx + 1}'],
      trueLocation: {'lat': userPoint['lat'], 'lon': userPoint['lon']},
      generatedSpoi: {'lat': meetingPoint.lat, 'lon': meetingPoint.lon},
      candidateSpois: userKNNs.take(k).map((p) => {'lat': p.lat, 'lon': p.lon}).toList(),
      kValue: k,
      seedInfo: '${DateTime.now().toUtc().toIso8601String()}Z',
      systemInformation: {
        'network_latency_ms': endTime.difference(startTime).inMilliseconds.toDouble(),
        'cpu_usage_pct': 0.0, // Placeholder
        'battery_level_pct': 0.0, // Placeholder
      },
      returnedContacts: [{
        'contact_id': 'U${contactIdx + 1}',
        'true_distance_m': calculateDistance(
          userPoint['lat'], userPoint['lon'],
          contactPoint['lat'], contactPoint['lon'],
        ),
        'near_distance_m': calculateDistance(
          userPoint['lat'], userPoint['lon'],
          meetingPoint.lat, meetingPoint.lon,
        ),
        'reported_rank': 1,
      }],
      meetingSuggestion: {
        'city_id': city['name'],
        'cluster_id': 1, // Placeholder
        'meeting_point': {'lat': meetingPoint.lat, 'lon': meetingPoint.lon},
        'accepted': true,
        'detour_ratio': detourRatio,
      },
    );
  }

  // Generate mock KNN points around a given location (simulating getKNNs behavior)
  static List<Point> generateMockKNNPoints(double centerLat, double centerLon, int k) {
    final random = Random();
    final points = <Point>[];
    
    for (int i = 0; i < k; i++) {
      // Generate points within ~500m radius
      final latOffset = (random.nextDouble() - 0.5) * 0.0045; // ~500m
      final lonOffset = (random.nextDouble() - 0.5) * 0.0045; // ~500m
      
      points.add(Point(centerLon + lonOffset, centerLat + latOffset));
    }
    
    return points;
  }

  static Future<void> runAllTests() async {
    final kValues = [5, 25, 100];
    final cities = [thessaloniki, komotini];
    final results = <TestResult>[];

    debugPrint('Starting detour ratio tests...');
    
    // Initialize the spatial database with a temporary path
    debugPrint('Initializing spatial database...');
    final tempDir = Directory.systemTemp;
    final dbPath = '${tempDir.path}/test_points.gpkg';
    await SpatialDb().openDbFileWithPath(dbPath);
    await SpatialDb().createSpatialTable(SpatialDb.pois);
    await SpatialDb().createCellsTable(SpatialDb.cells);
    
    // Note: getKNNs will download points from server/OSM as needed

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
            final result = await runTest(city, k, userIdx, contactIdx);
            results.add(result);
            debugPrint('    Detour ratio: ${result.meetingSuggestion['detour_ratio'].toStringAsFixed(2)}');
          } catch (e) {
            debugPrint('    Error: $e');
          }
        }
      }
    }

    // Save results
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final filename = 'test_results_$timestamp.json';
    final file = File(filename);
    await file.writeAsString(jsonEncode(results.map((r) => r.toJson()).toList()));
    debugPrint('\nResults saved to $filename');
    
    // Print summary statistics
    debugPrint('\n=== Summary Statistics ===');
    for (final city in cities) {
      debugPrint('\n${city['name']}:');
      for (final k in kValues) {
        final cityResults = results.where((r) => 
          r.meetingSuggestion['city_id'] == city['name'] && r.kValue == k
        ).toList();
        
        if (cityResults.isNotEmpty) {
          final avgDetourRatio = cityResults
              .map((r) => r.meetingSuggestion['detour_ratio'] as double)
              .reduce((a, b) => a + b) / cityResults.length;
          
          debugPrint('  k=$k: Average detour ratio = ${avgDetourRatio.toStringAsFixed(2)}');
        }
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Detour Ratio Tests', () {
    test('Run all detour ratio tests', () async {
      await DetourRatioTest.runAllTests();
    });
  });
}
