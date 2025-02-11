import 'dart:async';
import 'package:dart_jts/dart_jts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_near/services/db_helper.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class OSMService {
  static final OSMService _instance = OSMService._internal();
  factory OSMService() => _instance;
  
  bool _isDownloading = false;
  // About 500m grid cells (0.005 degrees ≈ 500m)
  static const double _gridSize = 0.005;

  OSMService._internal() {
    _initCellsTable();
  }

  Future<void> _initCellsTable() async {
    try {
      if (!DbHelper.db.hasTable(DbHelper.cells)) {
        DbHelper.db.execute('''
          CREATE TABLE IF NOT EXISTS ${DbHelper.cells.fixedName} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            min_lon REAL NOT NULL,
            max_lon REAL NOT NULL,
            min_lat REAL NOT NULL,
            max_lat REAL NOT NULL,
            downloaded_at INTEGER NOT NULL
          )
        ''');
        debugPrint('Created cells table');
      }
    } catch (e) {
      debugPrint('Error creating cells table: $e');
    }
  }

  List<Envelope> _splitIntoGridCells(Envelope boundingBox) {
    List<Envelope> cells = [];
    
    // Round to nearest grid size
    double minLon = (boundingBox.getMinX() / _gridSize).floor() * _gridSize;
    double maxLon = (boundingBox.getMaxX() / _gridSize).ceil() * _gridSize;
    double minLat = (boundingBox.getMinY() / _gridSize).floor() * _gridSize;
    double maxLat = (boundingBox.getMaxY() / _gridSize).ceil() * _gridSize;

    for (double lon = minLon; lon < maxLon; lon += _gridSize) {
      for (double lat = minLat; lat < maxLat; lat += _gridSize) {
        cells.add(Envelope(lon, lon + _gridSize, lat, lat + _gridSize));
      }
    }
    return cells;
  }

  Future<void> ensurePointsInArea(Envelope boundingBox) async {
    if (_isDownloading) return;
    _isDownloading = true;

    try {
      List<Envelope> cells = _splitIntoGridCells(boundingBox);
      debugPrint('Split area into ${cells.length} cells');

      for (var cell in cells) {
        // Check if cell exists in DB
        var result = DbHelper.db.select('''
          SELECT COUNT(*) as count FROM ${DbHelper.cells.fixedName}
          WHERE min_lon = ${cell.getMinX()} 
          AND max_lon = ${cell.getMaxX()}
          AND min_lat = ${cell.getMinY()}
          AND max_lat = ${cell.getMaxY()}
        ''');

        if (result.first.get('count') == 0) {
          debugPrint('Downloading new cell: ${cell.getMinX()},${cell.getMinY()}');
          await downloadPointsFromOSM(cell);
          
          // Mark as downloaded
          DbHelper.db.execute('''
            INSERT INTO ${DbHelper.cells.fixedName}
            (min_lon, max_lon, min_lat, max_lat, downloaded_at)
            VALUES (?, ?, ?, ?, ?)
          ''', arguments: [
            cell.getMinX(), cell.getMaxX(),
            cell.getMinY(), cell.getMaxY(),
            DateTime.now().millisecondsSinceEpoch
          ]);

          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    } catch (e) {
      debugPrint('Error ensuring points: $e');
    } finally {
      _isDownloading = false;
    }
  }

  Future<void> downloadPointsFromOSM(Envelope boundingBox) async {
    String url = 'https://overpass-api.de/api/map?bbox='
        '${boundingBox.getMinY()},${boundingBox.getMinX()},'
        '${boundingBox.getMaxY()},${boundingBox.getMaxX()}';
    
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final points = await compute(parsePoints, response.body);
      debugPrint('Downloaded ${points.length} points');

      for (var point in points) {
        await DbHelper().addPointToDb(point['lon']!, point['lat']!, DbHelper.pois);
      }
    } else {
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