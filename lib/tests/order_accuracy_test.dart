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
      final distance = random.nextDouble() * radiusMeters;
      contacts.add(calculateDestinationPoint(centerLat, centerLon, distance, angle * (180 / pi)));
    }
    
    return contacts;
  }

  // Get cloaked location using 2HP method
  static Future<Map<String, dynamic>> getCloakedLocation(
    double lat,
    double lon,
    int k,
    SpatialDb db,
    Random random
  ) async {
    // Get nearest point and its k neighbors
    final nearestPoint = await db.getKNNs(1, lon, lat, 50, SpatialDb.pois, SpatialDb.cells);
    final distance = Geolocator.distanceBetween(lat, lon, nearestPoint.first.lat, nearestPoint.first.lon);
    final knnPoints = await db.getKNNs(k, nearestPoint.first.lon, nearestPoint.first.lat, distance, SpatialDb.pois, SpatialDb.cells);
    
    // Select random point from k neighbors
    final selectedPoint = knnPoints[random.nextInt(knnPoints.length)];
    return {
      "lat": selectedPoint.lat,
      "lon": selectedPoint.lon,
      "candidate_spois": knnPoints.map((p) => {
        "lat": p.lat,
        "lon": p.lon,
      }).toList(),
    };
  }

  // Main test method
  static Future<void> runOrderAccuracyTest() async {
    final kValues = [5, 10, 25, 100, 500];
    final radiusValues = [500.0, 3000.0]; // meters
    const numContacts = 3;
    const numRepetitions = 5; //will make it later 300
    const locationChangeInterval = Duration(milliseconds: 300);
    
    final spatialDb = SpatialDb();
    final center = thessaloniki['center'];

    // Store results for final summary
    final results = <String, Map<int, double>>{};
    for (final radius in radiusValues) {
      results['${radius}m'] = {};
    }

    for (final radius in radiusValues) {
      debugPrint('\n=== Testing with radius: ${radius}m ===');
      
      for (final k in kValues) {
        var correctOrderCount = 0;
        
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

          // Get cloaked locations
          final userCloaked = await getCloakedLocation(
            userLocation['lat']!,
            userLocation['lon']!,
            k,
            spatialDb,
            random
          );

          final contactsCloaked = await Future.wait(
            contactLocations.map((contact) => getCloakedLocation(
              contact['lat']!,
              contact['lon']!,
              k,
              spatialDb,
              random
            ))
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

          // Calculate cloaked distances and rankings
          final cloakedDistances = contactsCloaked.map((contact) =>
            Geolocator.distanceBetween(
              userCloaked['lat'],
              userCloaked['lon'],
              contact['lat'],
              contact['lon']
            )
          ).toList();

          final cloakedOrder = List.generate(numContacts, (i) => i)
            ..sort((a, b) => cloakedDistances[a].compareTo(cloakedDistances[b]));

          // Check if orders match
          if (trueOrder.toString() == cloakedOrder.toString()) {
            correctOrderCount++;
          }

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
