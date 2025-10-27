import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:flutter_near/tests/helper.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DetourRatioTest {
    // Cache management methods
    static Future<void> saveClusters(Point point1, Point point2, List<NearCluster> clusters) async {
        final prefs = await SharedPreferences.getInstance();
        final key = '${point1.lon}_${point1.lat}_${point2.lon}_${point2.lat}';
        
        final clusterData = clusters.map((c) => {
            'id': c.id,
            'city_id': c.cityId,
            'city_name': c.cityName,
            'core_point': {'lat': c.corePoint.lat, 'lon': c.corePoint.lon},
        }).toList();
        
        await prefs.setString(key, jsonEncode(clusterData));
        debugPrint('Saved ${clusters.length} clusters to cache with key: $key');
    }

    static Future<List<NearCluster>?> getCachedClusters(Point point1, Point point2) async {
        final prefs = await SharedPreferences.getInstance();
        final key = '${point1.lon}_${point1.lat}_${point2.lon}_${point2.lat}';
        final data = prefs.getString(key);
        
        if (data == null) {
            debugPrint('No cached clusters found for key: $key');
            return null;
        }

        try {
            final List<dynamic> clusterData = jsonDecode(data);
            final clusters = clusterData.map((c) => NearCluster(
                id: c['id'],
                cityId: c['city_id'],
                cityName: c['city_name'],
                corePoint: Point(
                    c['core_point']['lon'],
                    c['core_point']['lat'],
                ),
            )).toList();
            debugPrint('Retrieved ${clusters.length} clusters from cache with key: $key');
            return clusters;
        } catch (e) {
            debugPrint('Error deserializing cached clusters: $e');
            return null;
        }
    }
    // Generate test points programmatically for consistent distances
    static List<Map<String, double>> generateTestPoints(double centerLat, double centerLon) {
        return [
            // Generate points at different distances and angles around the center (no center point)
            Helper.calculateDestinationPoint(centerLat, centerLon, 1000, -60),
            Helper.calculateDestinationPoint(centerLat, centerLon, 700, 30),
            Helper.calculateDestinationPoint(centerLat, centerLon, 600, 0),
        ];
    }

    // Generate test points programmatically for consistent distances
    static List<Map<String, double>> generateTrace(double centerLat, double centerLon) {
        return [
            {"lat": centerLat, "lon": centerLon},
            Helper.calculateDestinationPoint(centerLat, centerLon, 500, -10),
            Helper.calculateDestinationPoint(centerLat, centerLon, 550, 20),
            Helper.calculateDestinationPoint(centerLat, centerLon, 620, 60),
            Helper.calculateDestinationPoint(centerLat, centerLon, 670, -50),
        ];
    }

    // Detour Ratio Test Data
    static Map<String, dynamic> get thessaloniki => {
        "name": "ΘΕΣΣΑΛΟΝΙΚΗΣ",
        "city_id": "2335",
        "center": {"lat": 40.625163649564506, "lon": 22.959696666069682},
        // "center": {"lat": 40.663636138619154, "lon": 22.948311135074803},
    };

    static Map<String, dynamic> get komotini => {
        "name": "ΚΟΜΟΤΗΝΗΣ", 
        "city_id": "2595",
        "center": {"lat": 41.11827569692981, "lon": 25.40374006496843},
    };

  // Method to run a single test with visualization option
  static Future<void> runSingleTestWithVisualization(BuildContext context, Map<String, dynamic> city, int k, [String cloakingMode = "baseline_radius"]) async {
    debugPrint('Running single test: ${city['name']}, k=$k, User at point 1');
    
    try {
      final result = await DetourRatioTest().runDetourTest(city, k, 0, cloakingMode, 0, 0);
        debugPrint('Test completed. Average detour ratio: ${result['avg_detour_ratio'].toStringAsFixed(2)}');
      
      final detourRatios = result['detour_ratios'] as Map<String, dynamic>;
      for (final entry in detourRatios.entries) {
        debugPrint('  Contact ${entry.key}: ${entry.value.toStringAsFixed(2)}');
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
                  SizedBox(height: 8),
                  Text(
                    'Average Detour Ratio: ${result['avg_detour_ratio'].toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  SizedBox(height: 8),
                  Text('Detour Ratios by Pair:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...(result['detour_ratios'] as Map<String, dynamic>).entries.map((entry) => 
                    Text('  ${entry.key}: ${entry.value.toStringAsFixed(2)}')
                  ),
                  Text('City: ${result['city']}'),
                  Text('City ID: ${result['city_id']}'),
                  Text('Cluster ID: ${result['meeting_point']['cluster_id']}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Close'),
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
                    "candidate_spois": [],
                };
            case "baseline_grid":
                final cloaked = gridCloak(lat, lon, cellSizeMeters: cellSizeMeters);
                return {
                    "lat": cloaked["lat"]!,
                    "lon": cloaked["lon"]!,
                    "cloaking_method": "grid",
                    "cell_size_meters": cellSizeMeters,
                    "candidate_spois": [],
                };
            default:
                // For 2HP, get all candidate points and the selected one
                final nearestPoint = await db.getKNNs(1, lon, lat, 50, SpatialDb.pois, SpatialDb.cells);
                final distance = Geolocator.distanceBetween(lat, lon, nearestPoint.first.lat, nearestPoint.first.lon);
                final knnPoints = await db.getKNNs(k, nearestPoint.first.lon, nearestPoint.first.lat, distance, SpatialDb.pois, SpatialDb.cells);
                
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
        
        if (dUserContact == 0) return 1.0;  // Same point
        return (dUserMeeting + dContactMeeting) / dUserContact;
    }

    Future<void> runDetourRatioTest() async {
        debugPrint('Starting detour ratio tests...');
        
        final cities = [
          thessaloniki, 
          // komotini
        ];
        final cloakingConfigs = [
            {"mode": "baseline_radius", "radius": 50.0},
            {"mode": "baseline_radius", "radius": 100.0},
            {"mode": "baseline_radius", "radius": 200.0},
            {"mode": "baseline_radius", "radius": 250.0},
            {"mode": "baseline_radius", "radius": 500.0},
            {"mode": "baseline_radius", "radius": 750.0},
            {"mode": "baseline_radius", "radius": 1000.0},
            {"mode": "baseline_grid", "cell_size": 50.0},
            {"mode": "baseline_grid", "cell_size": 100.0},
            {"mode": "baseline_grid", "cell_size": 200.0},
            {"mode": "baseline_grid", "cell_size": 250.0},
            {"mode": "baseline_grid", "cell_size": 500.0},
            {"mode": "baseline_grid", "cell_size": 750.0},
            {"mode": "baseline_grid", "cell_size": 1000.0},
            {"mode": "2hp", "k": 5},
            {"mode": "2hp", "k": 10},
            {"mode": "2hp", "k": 25},
            {"mode": "2hp", "k": 50},
            {"mode": "2hp", "k": 100},
            {"mode": "2hp", "k": 200},
            {"mode": "2hp", "k": 250},
            {"mode": "2hp", "k": 500},
            {"mode": "2hp", "k": 750},
            {"mode": "2hp", "k": 1000},
        ];
        final results = <Map<String, dynamic>>[];

        for (final city in cities) {
            debugPrint('\nTesting city: ${city['name']}');

            // Generate a trace for U1 with 3 points
            final trace = generateTrace(city['center']['lat'], city['center']['lon']);
            final contactPoints = generateTestPoints(city['center']['lat'], city['center']['lon']);
            
            for (final config in cloakingConfigs) {
                final mode = config['mode'] as String;
                debugPrint('\nTesting with cloaking method: $mode');
                if (mode == 'baseline_radius') {
                    debugPrint('Using radius: ${config['radius']}m');
                } else if (mode == 'baseline_grid') {
                    debugPrint('Using cell size: ${config['cell_size']}m');
                } else if (mode == '2hp') {
                    debugPrint('Using k: ${config['k']}');
                }
                
                // For each point in the trace
                for (int traceIdx = 0; traceIdx < trace.length; traceIdx++) {
                    final prefs = await SharedPreferences.getInstance();
                    prefs.clear();
                    final tracePoint = trace[traceIdx];
                    debugPrint('\nTesting trace point ${traceIdx + 1}');
                    
                    // Run 5 times for each point
                    int runCount = 25;
                    for (int run = 0; run < runCount; run++) {
                        debugPrint('Run ${run + 1}/$runCount');
                        try {
                            // Create a custom test point list with the current trace point as U1
                            final testPoints = [
                                tracePoint,  // U1's position
                                ...contactPoints, // Other points as contacts
                            ];
                            
                            final result = await runDetourTest(
                                {...city, 'test_points': testPoints},
                                config['k'] as int? ?? 5,
                                0, // Always use index 0 as it's U1's position
                                mode,
                                config['radius'] as double? ?? 500.0,
                                config['cell_size'] as double? ?? 500.0
                            );
                            
                            results.add(result);
                            
                            final methodName = result['cloaking_method'];
                            debugPrint('Cloaking method: $methodName');
                            debugPrint('Average detour ratio: ${result['avg_detour_ratio'].toStringAsFixed(2)}');
                            
                            if (methodName == '2hp') {
                                final userCandidateCount = result['candidate_spois']?.length ?? 0;
                                debugPrint('Number of candidate SPOIs for U1: $userCandidateCount');
                                
                                // Print candidate SPOIs for contacts
                                for (final contact in result['contacts']) {
                                    final contactCandidateCount = contact['candidate_spois']?.length ?? 0;
                                    debugPrint('Number of candidate SPOIs for ${contact['contact_id']}: $contactCandidateCount');
                                }
                            }
                        } catch (e) {
                            debugPrint('Error: $e');
                        }
                    }
                }
            }
        }

        await shareResults(results);
    }

    Future<Map<String, dynamic>> runDetourTest(
        Map<String, dynamic> city,
        int k,
        int meetingAttempt,
        String cloakingMode,
        double radiusMeters,
        double cellSizeMeters
    ) async {
        // Setup test point for User A
        final userPoint = city['test_points'][0];
        
        // Create Point object for spatial database
        final userTrue = Point(userPoint['lon'], userPoint['lat']);
        
        // Create a single random generator for all SPOIs
        final spoiSeed = DateTime.now().millisecondsSinceEpoch;
        final spoiRandom = Random(spoiSeed);

        // Create a single SpatialDb instance to use for all queries
        final spatialDb = SpatialDb();

        // Get cloaked location for user A
        final userCloakedLocation = await getCloakedLocation(
            userTrue.lat,
            userTrue.lon,
            cloakingMode,
            k: k,
            radiusMeters: radiusMeters,
            cellSizeMeters: cellSizeMeters,
            db: spatialDb,
            random: spoiRandom,
        );

        // Create Point object for cloaked location
        final userSPOI = Point(userCloakedLocation["lon"]!, userCloakedLocation["lat"]!);
        
        // Store candidate SPOIs if available (for 2HP)
        final candidateSpois = userCloakedLocation["candidate_spois"];

        // Process all other test points as contacts
        final contacts = <Map<String, dynamic>>[];

          for (int contactIdx = 0; contactIdx < city['test_points'].length; contactIdx++) {
            if (contactIdx == 0) continue; // Skip self - avoid division by zero in detour ratio
            
            final contactPoint = city['test_points'][contactIdx];
            final contactSpatialPoint = Point(contactPoint['lon'], contactPoint['lat']);

            // Get cloaked location for contact using the same k value and random generator
            final cloakedLocationContact = await getCloakedLocation(
                contactSpatialPoint.lat,
                contactSpatialPoint.lon,
                cloakingMode,
                k: k,  // Use the same k value as the main user
                radiusMeters: radiusMeters,
                cellSizeMeters: cellSizeMeters,
                db: spatialDb,
                random: spoiRandom,  // Use the same random generator as the main user
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
                'candidate_spois': cloakedLocationContact["candidate_spois"] ?? [],
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
        final contactPoint = Point(
            firstContact['true_location']['lon'],
            firstContact['true_location']['lat'],
        );
        
        final clustersStartTime = DateTime.now();
        
        // Try to get clusters from cache first
        List<NearCluster>? clusters = await getCachedClusters(userTrue, contactPoint);
        
        // If not in cache, fetch from API and cache the result
        if (clusters == null) {
            clusters = await SpatialDb().getClustersBetweenTwoPoints(userTrue, contactPoint);
            if (clusters.isNotEmpty) {
                await saveClusters(userTrue, contactPoint, clusters);
            }
        }
        
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

        // final data = await ResourceMonitor.getResourceUsage;
        // final batteryLevel = (await Battery().batteryLevel).toDouble();
        
        return {
            // Test configuration
            'k_value': k,
            'city': city['name'],
            'city_id': selectedCluster.cityId,
            'cloaking_method': cloakingMode,
            'radius_meters': cloakingMode == 'baseline_radius' ? radiusMeters : null,
            'cell_size_meters': cloakingMode == 'baseline_grid' ? cellSizeMeters : null,
            'run_number': meetingAttempt + 1,

            // Timestamps and seeds
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'spoi_seed': spoiSeed,
            'meeting_seed': meetingSeed,

            // User and location data
            'user_id': 'U1',
            'true_location': {'lat': userPoint['lat'], 'lon': userPoint['lon']},
            'candidate_spois': candidateSpois ?? [],
            'generated_spoi': {
                'lat': userSPOI.lat,
                'lon': userSPOI.lon,
            },

            // Contact information
            'contact_ids': contacts.map((c) => c['contact_id']).toList(),
            'contacts': contacts,

            // Meeting and detour information
            'meeting_point': {
                'lat': meetingPoint.lat,
                'lon': meetingPoint.lon,
                'cluster_id': selectedCluster.id,
            },
            'detour_ratios': detourRatios,
            'avg_detour_ratio': avgDetourRatio,

            // System metrics
            'metrics': {
                'network_latency_ms': clustersEndTime.difference(clustersStartTime).inMilliseconds.toDouble(),
                // 'cpu_usage_pct': data.cpuInUseByApp,
                // 'battery_level_pct': batteryLevel,
                // 'memory_usage_bytes': data.memoryInUseByApp.toInt(),
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

    // Create XFile
    final file = XFile.fromData(
      jsonBytes,
      mimeType: 'application/json',
      name: filename,
    );

    try {
      // Share the file with proper positioning
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: [filename],
          text: 'Here are the test results',
          sharePositionOrigin: const Rect.fromLTWH(100, 100, 200, 200), // Provide valid position
        ),
      );
    } catch (e) {
      debugPrint('Share failed: $e');
      // Fallback: try without files, just text
      try {
        await SharePlus.instance.share(
          ShareParams(
            text: 'Test results generated: $filename',
            sharePositionOrigin: const Rect.fromLTWH(100, 100, 200, 200),
          ),
        );
      } catch (e2) {
        debugPrint('Fallback share also failed: $e2');
      }
    }
  }
}