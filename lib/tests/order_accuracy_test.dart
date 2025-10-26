import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:geolocator/geolocator.dart';

class OrderAccuracyTest {
  // Thessaloniki center coordinates (copied from detour ratio test)
  static Map<String, dynamic> get thessaloniki => {
    "name": "ΘΕΣΣΑΛΟΝΙΚΗΣ",
    "city_id": "2335",
    "center": {"lat": 40.625163649564506, "lon": 22.959696666069682},
  };

  // Helper function from detour ratio test to calculate points at a distance
  static Map<String, double> calculateDestinationPoint(double lat, double lon, double distanceMeters, double bearingDegrees) {
    const double earthRadius = 6371000; // Earth's radius in meters
    
    final double latRad = lat * (3.14159265359 / 180);
    final double lonRad = lon * (3.14159265359 / 180);
    final double bearingRad = bearingDegrees * (3.14159265359 / 180);
    
    final double angularDistance = distanceMeters / earthRadius;
    
    final double newLatRad = asin(
      sin(latRad) * cos(angularDistance) +
      cos(latRad) * sin(angularDistance) * cos(bearingRad)
    );
    
    final double newLonRad = lonRad + atan2(
      sin(bearingRad) * sin(angularDistance) * cos(latRad),
      cos(angularDistance) - sin(latRad) * sin(newLatRad)
    );
    
    return {
      'lat': newLatRad * (180 / 3.14159265359),
      'lon': newLonRad * (180 / 3.14159265359)
    };
  }

  // Generate random points within a specific radius
  static List<Map<String, double>> generateRandomContacts(
    double centerLat, 
    double centerLon, 
    double radiusMeters,
    int numContacts,
    Random random
  ) {
    final contacts = <Map<String, double>>[];
    
    for (var i = 0; i < numContacts; i++) {
      final angle = random.nextDouble() * 2 * pi;
      final distance = max(1.0, random.nextDouble() * radiusMeters);
      contacts.add(calculateDestinationPoint(centerLat, centerLon, distance, angle * (180 / pi)));
    }
    
    return contacts;
  }

  // Main test method
  static Future<void> runOrderAccuracyTest() async {
    final kValues = [5, 100, 250, 1000, 5000];
    final radiusValues = [500.0, 3000.0]; // meters
    const numContacts = 3;
    const numRepetitions = 300;
    const locationChangeInterval = Duration(milliseconds: 50);

    final spatialDb = SpatialDb();
    
    // Initialize database and load POIs from 5km.txt
    await spatialDb.emptyTable(SpatialDb.pois);
    await spatialDb.loadPoisFromFile('5km.txt');
    
    final center = thessaloniki['center'];

    // Store results for final summary
    final results = <String, Map<int, double>>{};
    for (final radius in radiusValues) {
      results['${radius}m'] = {};
    }

    for (final radius in radiusValues) {
      debugPrint('\n=== Testing with radius: ${radius}m ===');
      
      for (final k in kValues) {
        var correctOrderCount = 0.0;
        
        for (var rep = 0; rep < numRepetitions; rep++) {
          if (rep % 50 == 0) {
            debugPrint('Progress: ${rep ~/ 3}% for k=$k');
          }
          
          final random = Random(DateTime.now().millisecondsSinceEpoch);
          
          // Generate user's true location (center point)
          final userLocation = {
            'lat': center['lat'],
            'lon': center['lon']
          };

          // Generate random contacts within radius
          final contactLocations = generateRandomContacts(
            center['lat'],
            center['lon'],
            radius,
            numContacts,
            random
          );

          // Get nearest point and its k neighbors for user (2HP first step)
          final userNearestPoint = await spatialDb.getKNNs(1, userLocation['lon']!, userLocation['lat']!, 50, SpatialDb.pois, SpatialDb.cells, downloadMissingCells: false);
          final userDistance = Geolocator.distanceBetween(
            userLocation['lat']!,
            userLocation['lon']!,
            userNearestPoint.first.lat,
            userNearestPoint.first.lon
          );
          
          // Get k neighbors around nearest point (2HP second step)
          final userKnnPoints = await spatialDb.getKNNs(
            k,
            userNearestPoint.first.lon,
            userNearestPoint.first.lat,
            userDistance,
            SpatialDb.pois,
            SpatialDb.cells,
            downloadMissingCells: false
          );
          
          // Select random point as user's SPOI
          final userSPOI = userKnnPoints[random.nextInt(userKnnPoints.length)];

          // Get SPOIs for contacts using same process
          final contactSPOIs = await Future.wait(
            contactLocations.map((contact) async {
              final nearestPoint = await spatialDb.getKNNs(1, contact['lon']!, contact['lat']!, 50, SpatialDb.pois, SpatialDb.cells, downloadMissingCells: false);
              final distance = Geolocator.distanceBetween(
                contact['lat']!,
                contact['lon']!,
                nearestPoint.first.lat,
                nearestPoint.first.lon
              );
              final knnPoints = await spatialDb.getKNNs(
                k,
                nearestPoint.first.lon,
                nearestPoint.first.lat,
                distance,
                SpatialDb.pois,
                SpatialDb.cells,
                downloadMissingCells: false
              );
              return knnPoints[random.nextInt(knnPoints.length)];
            })
          );

          // Calculate true distances and rankings
          final trueDistances = contactLocations.map((contact) =>
            Geolocator.distanceBetween(
              userLocation['lat']!,
              userLocation['lon']!,
              contact['lat']!,
              contact['lon']!
            )
          ).toList();

          final trueOrder = List.generate(numContacts, (i) => i)
            ..sort((a, b) => trueDistances[a].compareTo(trueDistances[b]));

          // Calculate SPOI-based distances and rankings
          final spoiDistances = contactSPOIs.map((spoi) =>
            Geolocator.distanceBetween(
              userSPOI.lat,
              userSPOI.lon,
              spoi.lat,
              spoi.lon
            )
          ).toList();

          final spoiOrder = List.generate(numContacts, (i) => i)
            ..sort((a, b) => spoiDistances[a].compareTo(spoiDistances[b]));

          // Count preserved relative positions
          var preservedPositions = 0;
          var totalComparisons = 0;
          
          // Compare each pair of indices
          for (var i = 0; i < numContacts - 1; i++) {
            for (var j = i + 1; j < numContacts; j++) {
              totalComparisons++;
              
              // Get positions in true order
              final trueIdxI = trueOrder.indexOf(i);
              final trueIdxJ = trueOrder.indexOf(j);
              
              // Get positions in SPOI order
              final spoiIdxI = spoiOrder.indexOf(i);
              final spoiIdxJ = spoiOrder.indexOf(j);
              
              // Check if relative order is preserved
              if ((trueIdxI < trueIdxJ && spoiIdxI < spoiIdxJ) ||
                  (trueIdxI > trueIdxJ && spoiIdxI > spoiIdxJ)) {
                preservedPositions++;
              }
            }
          }
          
          // Add the percentage of preserved positions for this iteration
          correctOrderCount += (preservedPositions / totalComparisons);

          // Wait for location change interval
          await Future.delayed(locationChangeInterval);
        }

        final accuracy = (correctOrderCount / numRepetitions) * 100;
        results['${radius}m']![k] = accuracy;
        debugPrint('Order Accuracy for k=$k: ${accuracy.toStringAsFixed(1)}%');
      }
    }

    // Print final summary
    debugPrint('\n========== FINAL RESULTS ==========');
    for (final radius in radiusValues) {
      debugPrint('\nResults for radius: ${radius}m');
      debugPrint('k\tAccuracy');
      debugPrint('-------------------');
      for (final k in kValues) {
        final accuracy = results['${radius}m']![k]!;
        debugPrint('$k\t${accuracy.toStringAsFixed(1)}%');
      }
    }
  }
}
