import 'dart:async';
import 'package:dart_jts/dart_jts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_near/services/db_helper.dart';
import 'package:http/http.dart' as http;

class OSMService {
  static final OSMService _instance = OSMService._internal();
  factory OSMService() => _instance;
  
  bool _isDownloading = false;
  static const double _gridSize = 0.01; // About 1km grid cells

  OSMService._internal() {
    _initCellsTable();
  }

  Future<void> _initCellsTable() async {
    try {
      if (!DbHelper.db.hasTable(DbHelper.cells)) {
        DbHelper.db.execute('''
          CREATE TABLE IF NOT EXISTS ${DbHelper.cells.fixedName} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bounds POLYGON NOT NULL,  -- Store the bounding box as a polygon
            downloaded_at INTEGER
          )
        ''');
        debugPrint('Created cells table');
      }
    } catch (e) {
      debugPrint('Error creating cells table: $e');
    }
  }

  Future<List<Envelope>> _getMissingAreas(Envelope boundingBox) async {
    List<Envelope> gridCells = _splitIntoGridCells(boundingBox);
    List<Envelope> missingAreas = [];

    try {
      for (var cell in gridCells) {
        // Check if this cell intersects with any downloaded area
        var result = DbHelper.db.select('''
          SELECT COUNT(*) as count 
          FROM ${DbHelper.cells.fixedName}
          WHERE ST_Intersects(
            bounds, 
            ST_GeomFromText('POLYGON((
              ${cell.getMinX()} ${cell.getMinY()},
              ${cell.getMaxX()} ${cell.getMinY()},
              ${cell.getMaxX()} ${cell.getMaxY()},
              ${cell.getMinX()} ${cell.getMaxY()},
              ${cell.getMinX()} ${cell.getMinY()}
            ))')
          )
        ''');

        int count = result.first.get('count');
        if (count == 0) {
          missingAreas.add(cell);
        }
      }
    } catch (e) {
      debugPrint('Error checking missing areas: $e');
    }

    return missingAreas;
  }

  Future<void> _markCellAsDownloaded(Envelope cell) async {
    try {
      DbHelper.db.execute('''
        INSERT INTO ${DbHelper.cells.fixedName} (bounds, downloaded_at)
        VALUES (
          ST_GeomFromText('POLYGON((
            ${cell.getMinX()} ${cell.getMinY()},
            ${cell.getMaxX()} ${cell.getMinY()},
            ${cell.getMaxX()} ${cell.getMaxY()},
            ${cell.getMinX()} ${cell.getMaxY()},
            ${cell.getMinX()} ${cell.getMinY()}
          ))'),
          ?
        )
      ''', arguments: [DateTime.now().millisecondsSinceEpoch]);
    } catch (e) {
      debugPrint('Error marking cell as downloaded: $e');
    }
  }

  // Convert envelope to grid cells
  List<Envelope> _splitIntoGridCells(Envelope boundingBox) {
    List<Envelope> cells = [];
    
    double minLon = (boundingBox.getMinX() / _gridSize).floor() * _gridSize;
    double maxLon = (boundingBox.getMaxX() / _gridSize).ceil() * _gridSize;
    double minLat = (boundingBox.getMinY() / _gridSize).floor() * _gridSize;
    double maxLat = (boundingBox.getMaxY() / _gridSize).ceil() * _gridSize;

    for (double lon = minLon; lon < maxLon; lon += _gridSize) {
      for (double lat = minLat; lat < maxLat; lat += _gridSize) {
        cells.add(Envelope(
          lon, 
          lon + _gridSize,
          lat, 
          lat + _gridSize
        ));
      }
    }
    return cells;
  }

  String _getCellKey(Envelope cell) {
    return '${cell.getMinX().toStringAsFixed(3)},${cell.getMinY().toStringAsFixed(3)}';
  }

  Future<void> ensurePointsInArea(Envelope boundingBox) async {
    if (_isDownloading) return;
    _isDownloading = true;

    try {
      debugPrint('Checking for missing areas in bounding box');
      List<Envelope> missingAreas = await _getMissingAreas(boundingBox);
      
      if (missingAreas.isNotEmpty) {
        debugPrint('Found ${missingAreas.length} areas to download');
        for (var cell in missingAreas) {
          debugPrint('Downloading cell: ${_getCellKey(cell)}');
          await downloadPointsFromOSM(cell);
          await _markCellAsDownloaded(cell);
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } else {
        debugPrint('No missing areas to download');
      }
    } catch (e) {
      debugPrint('Error downloading OSM data: $e');
    } finally {
      _isDownloading = false;
    }
  }

  // Updated to use DB for coverage calculation
  Future<double> getAreaCoverage(Envelope boundingBox) async {
    List<Envelope> gridCells = _splitIntoGridCells(boundingBox);
    List<Envelope> missingAreas = await _getMissingAreas(boundingBox);
    
    return (gridCells.length - missingAreas.length) / gridCells.length;
  }

  Future<void> downloadPointsFromOSM(Envelope boundingBox) async{
    double minLon = boundingBox.getMinY();
    double minLat = boundingBox.getMinX();
    double maxLon = boundingBox.getMaxY();
    double maxLat = boundingBox.getMaxX();

    // Define the URL
    String url = 'https://overpass-api.de/api/map?bbox=$minLat,$minLon,$maxLat,$maxLon';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final pointsData = await compute(parsePoints, response.body);
      debugPrint('Downloaded and parsed ${pointsData.length} points');

      if (pointsData.isNotEmpty) {
        for (Map<String, double> point in pointsData) {
          await DbHelper().addPointToDb(point['lon']!, point['lat']!, DbHelper.pois);
        }
        debugPrint('Inserted ${await DbHelper().getRowCount(DbHelper.pois)} points');
      }
    } else {
      debugPrint('Failed to download the file. Status code: ${response.statusCode}');
    }
  }
} 