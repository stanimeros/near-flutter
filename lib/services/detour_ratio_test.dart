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

    // Generate a trace of 3 points with 200-300m distance between them
    static List<Map<String, double>> generateTrace(double startLat, double startLon) {
        final random = Random();
        final trace = <Map<String, double>>[
            {"lat": startLat, "lon": startLon}  // Starting point
        ];

        // Generate 2 more points with random distances (200-300m) and angles
        for (int i = 0; i < 2; i++) {
            final prevPoint = trace.last;
            final distance = 200.0 + random.nextDouble() * 100; // Random distance between 200-300m
            final angle = random.nextDouble() * 360; // Random angle
            final nextPoint = calculateDestinationPoint(prevPoint['lat']!, prevPoint['lon']!, distance, angle);
            trace.add(nextPoint);
        }

        return trace;
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
  static Future<void> runSingleTestWithVisualization(BuildContext context, Map<String, dynamic> city, int k, int userIdx, [String cloakingMode = "baseline_radius"]) async {
    debugPrint('Running single test: ${city['name']}, k=$k, User at point ${userIdx + 1}');
    
    try {
      final result = await DetourRatioTest().runDetourTest(city, k, userIdx, 0, cloakingMode);
      debugPrint('Test completed. Average detour ratio: ${result['meeting_suggestion']['avg_detour_ratio'].toStringAsFixed(2)}');
      
      final detourRatios = result['meeting_suggestion']['detour_ratios'] as Map<String, dynamic>;
      for (final entry in detourRatios.entries) {
        debugPrint('  Pair U${entry.key}: ${entry.value.toStringAsFixed(2)}');
      }
      
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
                    'Average Detour Ratio: ${result['meeting_suggestion']['avg_detour_ratio'].toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  SizedBox(height: 8),
                  Text('Detour Ratios by Pair:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...(result['meeting_suggestion']['detour_ratios'] as Map<String, dynamic>).entries.map((entry) => 
                    Text('  U${entry.key}: ${entry.value.toStringAsFixed(2)}')
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

    // Fixed radius cloaking method
    static Map<String, double> fixedRadiusCloak(double lat, double lon, {double radiusMeters = 500, Random? random}) {
        final rand = random ?? Random();
        final angle = rand.nextDouble() * 2 * pi;
        final dist = rand.nextDouble() * radiusMeters;

        final deltaLat = (dist * cos(angle)) / 111000;
        final deltaLon = (dist * sin(angle)) / (111000 * cos(lat * pi / 180));

        return {
            "lat": lat + deltaLat,
            "lon": lon + deltaLon,
        };
    }

    // Grid-based cloaking method
    static Map<String, double> gridCloak(double lat, double lon, {double cellSizeMeters = 500}) {
        final latMeters = 111000.0;
        final lonMeters = 111000.0 * cos(lat * pi / 180);

        final x = lon * lonMeters;
        final y = lat * latMeters;

        final xSnap = (x / cellSizeMeters).round() * cellSizeMeters;
        final ySnap = (y / cellSizeMeters).round() * cellSizeMeters;

        final cloakedLon = xSnap / lonMeters;
        final cloakedLat = ySnap / latMeters;

        return {
            "lat": cloakedLat,
            "lon": cloakedLon,
        };
    }

    // Two-hop privacy method (existing implementation)
    static Future<Point> twoHopPrivacy(double lat, double lon, int k, SpatialDb db, {Random? random}) async {
        // Step 1: Get 1 nearest point
        final nearestPoint = await db.getKNNs(1, lon, lat, 50, SpatialDb.pois, SpatialDb.cells);
        
        // Step 2: Get k nearest points from nearest point location
        final knnPoints = await db.getKNNs(k, nearestPoint.first.lon, nearestPoint.first.lat, 50, SpatialDb.pois, SpatialDb.cells);

        if (knnPoints.isEmpty) {
            throw Exception('No KNN points found');
        }

        // Select random point from k nearest points using provided or new random generator
        final rand = random ?? Random();
        return knnPoints[rand.nextInt(knnPoints.length)];
    }

    // Get cloaked location based on mode
    static Future<Map<String, dynamic>> getCloakedLocation(
        double lat, 
        double lon, 
        String mode, 
        {int k = 5, 
        double radiusMeters = 500, 
        double cellSizeMeters = 500,
        required SpatialDb db,
        Random? random}
    ) async {
        final rand = random ?? Random();
        
        switch (mode) {
            case "baseline_radius":
                final cloaked = fixedRadiusCloak(lat, lon, radiusMeters: radiusMeters, random: rand);
                return {
                    "lat": cloaked["lat"]!,
                    "lon": cloaked["lon"]!,
                    "cloaking_method": "fixed_radius",
                    "radius_meters": radiusMeters,
                    "candidate_spois": null,
                };
            case "baseline_grid":
                final cloaked = gridCloak(lat, lon, cellSizeMeters: cellSizeMeters);
                return {
                    "lat": cloaked["lat"]!,
                    "lon": cloaked["lon"]!,
                    "cloaking_method": "grid",
                    "cell_size_meters": cellSizeMeters,
                    "candidate_spois": null,
                };
            default:
                // For 2HP, get all candidate points and the selected one
                final nearestPoint = await db.getKNNs(1, lon, lat, 50, SpatialDb.pois, SpatialDb.cells);
                final knnPoints = await db.getKNNs(k, nearestPoint.first.lon, nearestPoint.first.lat, 50, SpatialDb.pois, SpatialDb.cells);
                
                final selectedPoint = knnPoints[rand.nextInt(knnPoints.length)];
                return {
                    "lat": selectedPoint.lat,
                    "lon": selectedPoint.lon,
                    "cloaking_method": "2hp",
                    "k_value": k,
                    "candidate_spois": knnPoints.map((p) => {
                        "lat": p.lat,
                        "lon": p.lon,
                    }).toList(),
                };
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
        
        final kValues = [5, 10, 25, 100];
        final cities = [thessaloniki, komotini];
        final cloakingModes = ["baseline_radius", "baseline_grid", "2hp"];
        final results = <Map<String, dynamic>>[];

        for (final city in cities) {
            debugPrint('\nTesting city: ${city['name']}');
            
            // Generate a trace for U1 with 3 points
            final trace = generateTrace(city['center']['lat'], city['center']['lon']);
            debugPrint('\nGenerated trace with ${trace.length} points:');
            for (int i = 0; i < trace.length; i++) {
                debugPrint('  Point ${i + 1}: (${trace[i]['lat']}, ${trace[i]['lon']})');
            }
            
            for (final k in kValues) {
                debugPrint('\nTesting with k=$k');
                
                for (final mode in cloakingModes) {
                    debugPrint('\nTesting with cloaking method: $mode');
                    
                    // For each point in the trace
                    for (int traceIdx = 0; traceIdx < trace.length; traceIdx++) {
                        final tracePoint = trace[traceIdx];
                        debugPrint('\nTesting trace point ${traceIdx + 1}');
                        
                        // Run 5 times for each point
                        for (int run = 0; run < 5; run++) {
                            debugPrint('Run ${run + 1}/5');
                            try {
                                // Create a custom test point list with the current trace point as U1
                                final testPoints = [
                                    tracePoint,  // U1's position
                                    ...city['test_points'], // Other points as contacts
                                ];
                                
                                final result = await runDetourTest(
                                    {...city, 'test_points': testPoints},
                                    k,
                                    0, // Always use index 0 as it's U1's position
                                    run,
                                    mode
                                );
                                
                                // Add trace information to the result
                                result['trace_info'] = {
                                    'point_index': traceIdx,
                                    'total_points': trace.length,
                                    'run': run + 1,
                                    'trace': trace,
                                };
                                
                                results.add(result);
                                
                                final methodName = result['cloaking_method'];
                                debugPrint('Cloaking method: $methodName');
                                debugPrint('Average detour ratio: ${result['meeting_suggestion']['avg_detour_ratio'].toStringAsFixed(2)}');
                                debugPrint('Number of contacts: ${result['returned_contacts'].length}');
                                
                                if (methodName == '2hp') {
                                    final candidateCount = result['generated_spoi']['candidate_spois']?.length ?? 0;
                                    debugPrint('Number of candidate SPOIs: $candidateCount');
                                }
                            } catch (e) {
                                debugPrint('Error: $e');
                                await Future.delayed(Duration(seconds: 2));
                            }
                        }
                    }
                    
                    // Add extra delay between different cloaking modes
                    if (mode != cloakingModes.last) {
                        debugPrint('Completed $mode tests');
                        await Future.delayed(Duration(seconds: 1));
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
            for (final mode in cloakingModes) {
                debugPrint('\nCloaking Method: $mode');
                for (final k in kValues) {
                    debugPrint('\n  k=$k:');
                    final cityResults = results.where((r) => 
                        r['meeting_suggestion']['city_id'] == city['city_id'] && 
                        r['k_value'] == k &&
                        r['cloaking_method'] == mode
                    ).toList();
                    
                    if (cityResults.isNotEmpty) {
                        // Group results by trace point
                        final traceResults = <int, List<Map<String, dynamic>>>{};
                        for (final result in cityResults) {
                            final pointIndex = result['trace_info']['point_index'] as int;
                            traceResults.putIfAbsent(pointIndex, () => []).add(result);
                        }

                        // Print results for each trace point
                        for (final pointIndex in traceResults.keys.toList()..sort()) {
                            final pointResults = traceResults[pointIndex]!;
                            final traceInfo = pointResults.first['trace_info'];
                            
                            debugPrint('\n    Trace Point ${pointIndex + 1}/${traceInfo['total_points']}:');
                            debugPrint('      True Location: (${traceInfo['trace'][pointIndex]['lat']}, ${traceInfo['trace'][pointIndex]['lon']})');
                            
                            // Print results for each run
                            for (final result in pointResults) {
                                debugPrint('\n      Run ${result['trace_info']['run']}/5:');
                                debugPrint('        Generated SPOI: (${result['generated_spoi']['lat']}, ${result['generated_spoi']['lon']})');
                                debugPrint('        Average Detour Ratio: ${result['meeting_suggestion']['avg_detour_ratio'].toStringAsFixed(2)}');
                                
                                // Print candidate SPOIs for 2HP
                                final candidateSpois = result['generated_spoi']['candidate_spois'];
                                if (candidateSpois != null) {
                                    debugPrint('        Candidate SPOIs (${candidateSpois.length}):');
                                    for (final spoi in candidateSpois) {
                                        debugPrint('          (${spoi['lat']}, ${spoi['lon']})');
                                    }
                                }
                                
                                // Print detour ratios for each contact
                                final detourRatios = result['meeting_suggestion']['detour_ratios'] as Map<String, dynamic>;
                                debugPrint('        Contact Detour Ratios:');
                                for (final entry in detourRatios.entries) {
                                    debugPrint('          ${entry.key}: ${entry.value.toStringAsFixed(2)}');
                                }
                            }
                            
                            // Calculate and print average detour ratio for this trace point
                            final avgDetourRatio = pointResults
                                .map((r) => r['meeting_suggestion']['avg_detour_ratio'] as double)
                                .reduce((a, b) => a + b) / pointResults.length;
                            debugPrint('\n      Average detour ratio across all runs: ${avgDetourRatio.toStringAsFixed(2)}');
                        }
                    }
                }
            }
        }
    }

    Future<Map<String, dynamic>> runDetourTest(
        Map<String, dynamic> city,
        int k,
        int userIdx,
        int meetingAttempt,
        [String cloakingMode = "baseline_radius"]
    ) async {
        // Setup test point for User A
        final userPoint = city['test_points'][userIdx];
        
        // Create Point object for spatial database
        final userSpatialPoint = Point(userPoint['lon'], userPoint['lat']);
        
        // Create a single random generator for all SPOIs
        final spoiSeed = DateTime.now().millisecondsSinceEpoch;
        final spoiRandom = Random(spoiSeed);

        // Create a single SpatialDb instance to use for all queries
        final spatialDb = SpatialDb();

        // Get cloaked location for user A
        final userCloakedLocation = await getCloakedLocation(
            userSpatialPoint.lat,
            userSpatialPoint.lon,
            cloakingMode,
            k: k,
            radiusMeters: 500,
            cellSizeMeters: 500,
            db: spatialDb,
            random: spoiRandom,
        );

        // Create Point object for cloaked location
        final userSPOI = Point(userCloakedLocation["lon"]!, userCloakedLocation["lat"]!);

        // Process all other test points as contacts
        final contacts = <Map<String, dynamic>>[];

        for (int contactIdx = 0; contactIdx < city['test_points'].length; contactIdx++) {
            if (contactIdx == userIdx) continue; // Skip self

            final contactPoint = city['test_points'][contactIdx];
            final contactSpatialPoint = Point(contactPoint['lon'], contactPoint['lat']);

            // Get cloaked location for contact using the same random generator
            final cloakedLocationContact = await getCloakedLocation(
                contactSpatialPoint.lat,
                contactSpatialPoint.lon,
                cloakingMode,
                k: k,
                radiusMeters: 500,
                cellSizeMeters: 500,
                db: spatialDb,
                random: spoiRandom,
            );

            final contactSPOI = Point(cloakedLocationContact["lon"]!, cloakedLocationContact["lat"]!);
            
            // Calculate distances
            final trueDistance = Geolocator.distanceBetween(
                userPoint['lat'], userPoint['lon'],
                contactPoint['lat'], contactPoint['lon'],
            );
            final nearDistance = Geolocator.distanceBetween(
                userSPOI.lat, userSPOI.lon,
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
            userSPOI,
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
        
        // Calculate detour ratios for each user-contact pair
        final detourRatios = <String, double>{};
        var totalDetourRatio = 0.0;
        
        for (final contact in contacts) {
            final detourRatio = calculateDetourRatio(
                userPoint['lat'], userPoint['lon'],
                contact['true_location']['lat'], contact['true_location']['lon'],
                meetingPoint.lat, meetingPoint.lon,
            );
            detourRatios[contact['contact_id']] = detourRatio;
            totalDetourRatio += detourRatio;
        }

        // Calculate average detour ratio
        final avgDetourRatio = contacts.isEmpty ? 0.0 : totalDetourRatio / contacts.length;

        final data = await ResourceMonitor.getResourceUsage;
        final batteryLevel = (await Battery().batteryLevel).toDouble();
        
        return {
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'user_id': 'U${userIdx + 1}',
            'contact_ids': contacts.map((c) => c['contact_id']).toList(),
            'true_location': {'lat': userPoint['lat'], 'lon': userPoint['lon']},
            'generated_spoi': {
                'lat': userSPOI.lat,
                'lon': userSPOI.lon,
            },
            'k_value': k,
            'radius_meters': 500,
            'cell_size_meters': 500,
            'cloaking_method': cloakingMode,
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
                'detour_ratios': detourRatios,
                'avg_detour_ratio': avgDetourRatio,
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