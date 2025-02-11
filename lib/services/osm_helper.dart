import 'dart:async';
import 'package:dart_jts/dart_jts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_near/services/db_helper.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class OSMHelper {
  
  bool _isDownloading = false;
  // About 200m grid cells (0.002 degrees ≈ 200m)
  static const double _gridSize = 0.002;
  static const double metersPerDegree = 111000.0;  // at equator

  // Convert lat/lon to grid coordinates
  (int, int) _getGridCoordinates(double lon, double lat) {
    int x = (lon / _gridSize).floor();
    int y = (lat / _gridSize).floor();
    return (x, y);
  }

  // Convert grid coordinates to bounding box
  Envelope _getCellBoundingBox(int x, int y) {
    double minLon = x * _gridSize;
    double maxLon = (x + 1) * _gridSize;
    double minLat = y * _gridSize;
    double maxLat = (y + 1) * _gridSize;
    // Create envelope in (lon, lat) order as expected by JTS
    return Envelope(minLon, maxLon, minLat, maxLat);
  }

  Future<void> ensurePointsInArea(Envelope boundingBox) async {
    if (_isDownloading) return;
    _isDownloading = true;

    try {
      // Get grid coordinates for bounding box corners
      var (minX, minY) = _getGridCoordinates(boundingBox.getMinX(), boundingBox.getMinY());
      var (maxX, maxY) = _getGridCoordinates(boundingBox.getMaxX(), boundingBox.getMaxY());
      
      debugPrint('Checking grid cells from ($minX,$minY) to ($maxX,$maxY)');

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          // Check if cell exists
          var result = DbHelper.db.select('''
            SELECT COUNT(*) as count FROM ${DbHelper.cells.fixedName}
            WHERE cell_x = $x AND cell_y = $y
          ''');

          if (result.first.get('count') == 0) {
            debugPrint('Downloading cell ($x,$y)');
            var cellBox = _getCellBoundingBox(x, y);
            await downloadPointsFromOSM(cellBox);
            
            // Mark cell as downloaded
            DbHelper.db.execute('''
              INSERT INTO ${DbHelper.cells.fixedName}
              (cell_x, cell_y, downloaded_at)
              VALUES (?, ?, ?)
            ''', arguments: [x, y, DateTime.now().millisecondsSinceEpoch]);

            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    } catch (e) {
      debugPrint('Error ensuring points: $e');
    } finally {
      _isDownloading = false;
    }
  }

  Future<void> downloadPointsFromOSM(Envelope boundingBox) async {
    // OSM API expects: min_lon,min_lat,max_lon,max_lat
    String url = 'https://overpass-api.de/api/map?bbox='
        '${boundingBox.getMinX()},${boundingBox.getMinY()},'  // min_lon,min_lat
        '${boundingBox.getMaxX()},${boundingBox.getMaxY()}';  // max_lon,max_lat
    
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final points = await compute(parsePoints, response.body);
      debugPrint('Downloaded ${points.length} points');

      for (var point in points) {
        await DbHelper().addPointToDb(point['lon']!, point['lat']!);
      }
    } else {
      debugPrint('Failed request URL: $url');
      debugPrint('Response body: ${response.body}');
      throw Exception('Failed to download points: ${response.statusCode}');
    }
  }
}

// Helper function to parse XML and extract points data in an isolate
List<Map<String, double>> parsePoints(String xmlString){
  final document = XmlDocument.parse(xmlString);
  return document.findAllElements('node').map((point) {
    final lon = point.getAttribute('lon');
    final lat = point.getAttribute('lat');
    if (lon != null && lat != null) {
      return {'lon': double.parse(lon), 'lat': double.parse(lat)};
    }
    return null;
  }).whereType<Map<String, double>>().toList();
}