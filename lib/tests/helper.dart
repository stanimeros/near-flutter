import 'dart:math';

class Helper {
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
}