import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'package:flutter/foundation.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'package:dart_hydrologis_db/dart_hydrologis_db.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class Point {
  double lon;
  double lat;

  Point(this.lon, this.lat);
}

class GridCell {
  int lon;
  int lat;

  GridCell(this.lon, this.lat);

  getKey() {
    return '$lon,$lat';
  }
}

class BoundingBox {
  double minLon;
  double maxLon;
  double minLat;
  double maxLat;
  late jts.Envelope envelope;

  BoundingBox(this.minLon, this.maxLon, this.minLat, this.maxLat) {
    envelope = jts.Envelope(
      minLon,
      maxLon,
      minLat,
      maxLat,
    );
  }
}

class SpatialDb {
  static late GeopackageDb db;
  static const int clusters = 20;
  static const double metersPerDegree = 111000.0;
  static String dbFilename = 'points.gpkg';
  static TableName pois = TableName("pois", schemaSupported: false);
  static TableName cells = TableName("cells", schemaSupported: false);
  
  // Function to initialize the database
  Future<void> openDbFile() async {
    try {
      ConnectionsHandler ch = ConnectionsHandler();
      Directory directory = await getApplicationDocumentsDirectory();
      String dbPath = '${directory.path}/$dbFilename';
      db = ch.open(dbPath);
      db.openOrCreate();
      db.forceRasterMobileCompatibility = false;
      debugPrint('Database ready');
    } catch(e) {
      debugPrint(e.toString());
    }
  }

  Future<void> deleteDbFile() async {
    try{
      Directory directory = await getApplicationDocumentsDirectory();
      String dbPath = '${directory.path}/$dbFilename';
      
      File file = File(dbPath);
      // Check if the file exists
      if (await file.exists()) {
        // Delete the file
        await file.delete();
        debugPrint('File deleted: $dbPath');
      } else {
        debugPrint('File does not exist: $dbPath');
      }
    }catch(e){
      debugPrint(e.toString());
    }
  }

  Future<void> createSpatialTable() async {
    try {
      if (!db.hasTable(pois)){
        db.createSpatialTable(
          pois,
          4326,
          "geopoint POINT UNIQUE",
          ["id INTEGER PRIMARY KEY AUTOINCREMENT"],
          null,
          false,
        );

        debugPrint('Spatial table created');
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> createCellsTable() async {
    try {
      if (!db.hasTable(cells)) {
        db.createSpatialTable(
          cells,
          4326,
          "cell_lon INTEGER, cell_lat INTEGER",
          ["id INTEGER PRIMARY KEY AUTOINCREMENT"],
          null,
          false,
        );

        debugPrint('Cells table created');
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // Function to clean the database
  Future<void> emptyTable(TableName table) async {
    try {
      if (db.hasTable(table)) {
        db.execute("DELETE FROM ${table.fixedName}");
        debugPrint('Table ${table.fixedName} emptied');
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> addCellToDb(GridCell cell) async {
    String sql = "INSERT OR IGNORE INTO ${cells.fixedName} (cell_lon, cell_lat) VALUES (?, ?);";
    db.execute(sql, arguments: [cell.lon, cell.lat]);
  }

  Future<List<GridCell>> getCellsInArea(BoundingBox boundingBox, double gridSize) async {
    List<GridCell> cellsInArea = [];
    try {
      // Calculate cell indices
      int minLon = (boundingBox.minLon / gridSize).floor();
      int maxLon = (boundingBox.maxLon / gridSize).floor();
      int minLat = (boundingBox.minLat / gridSize).floor();
      int maxLat = (boundingBox.maxLat / gridSize).floor();
      
      // Calculate total number of cells
      int totalCells = (maxLon - minLon + 1) * (maxLat - minLat + 1);
      if (totalCells > 8) {
        debugPrint('Too many cells: $totalCells > 8');
        return [];
      }
      
      debugPrint('Grid area ($totalCells): ($minLon,$minLat) to ($maxLon,$maxLat)');

      for (int lon = minLon; lon <= maxLon; lon++) {
        for (int lat = minLat; lat <= maxLat; lat++) {
          cellsInArea.add(GridCell(lon, lat));
        }
      }
      
      return cellsInArea;
    } catch(e) {
      debugPrint('Error in getCellsInArea: $e');
    }
    return [];
  }

  Future<List<BoundingBox>> downloadCellsInArea(BoundingBox boundingBox) async {
    double gridSize = 0.005;
    List<BoundingBox> downloadedCells = [];
    try {
      List<GridCell> gridCells = await getCellsInArea(boundingBox, gridSize);
      
      // Calculate cell indices for the query
      int minLonCell = (boundingBox.minLon / gridSize).floor();
      int maxLonCell = (boundingBox.maxLon / gridSize).floor();
      int minLatCell = (boundingBox.minLat / gridSize).floor();
      int maxLatCell = (boundingBox.maxLat / gridSize).floor();
      
      // Get existing cells using the cell indices
      final existingCells = db.select(
        'SELECT cell_lon, cell_lat FROM ${cells.fixedName} WHERE cell_lon BETWEEN $minLonCell AND $maxLonCell AND cell_lat BETWEEN $minLatCell AND $maxLatCell'
      );

      Set<String> existingSet = {};
      existingCells.forEach(
        (row) => existingSet.add('${row.get("cell_lon")},${row.get("cell_lat")}')
      );

      debugPrint('Found ${existingSet.length} existing cells');

      // Count cells that need downloading
      int cellsToDownload = 0;
      for (GridCell cell in gridCells) {
        final cellKey = cell.getKey();
        if (!existingSet.contains(cellKey)) {
          cellsToDownload++;
        }
      }

      if (cellsToDownload > 4) {
        debugPrint('Too many cells to download: $cellsToDownload > 4');
        return [];
      }

      // Process each cell in the grid
      for (GridCell cell in gridCells) {
        final cellKey = cell.getKey();

        if (!existingSet.contains(cellKey)) {
          debugPrint('Downloading new cell $cellKey: ${cell.lon},${cell.lat}');
          await addCellToDb(cell);
          BoundingBox boundingBox = BoundingBox(cell.lon * gridSize, (cell.lon + 1) * gridSize, cell.lat * gridSize, (cell.lat + 1) * gridSize);
          List<Point> points = await downloadPointsFromServer(boundingBox);
          if (points.isEmpty) {
            points = await downloadPointsFromOSM(boundingBox);
          }
        }
        
        downloadedCells.add(boundingBox);
      }

      return downloadedCells;
    } catch(e) {
      debugPrint('Error in downloadCellsInArea: $e');
    }
    return [];
  }

  // Function to get points within a bounding box
  Future<List<Point>> getPointsInBoundingBox(BoundingBox boundingBox) async {
    List<Point> list = [];
    DateTime before = DateTime.now();
    List<jts.Geometry?> geometries = db.getGeometriesIn(
      pois, envelope: boundingBox.envelope
    );
    DateTime after = DateTime.now();
    debugPrint('Query took ${after.difference(before).inMilliseconds.toString()}ms');

    for (var geometry in geometries) {
      if (geometry is jts.Point) {
        list.add(Point(geometry.getX(), geometry.getY()));
      }
    }
    return list;
  }

  Future<Point> getRandomKNN(int k, double lon, double lat, double bufferMeters) async {
    List<Point> list = [];

    while (list.length < k) {
      debugPrint('Creating bbox with side ${bufferMeters*2}m');
      BoundingBox boundingBox = await createBufferBoundingBox(lon, lat, bufferMeters);
      // Get cells in the updated bounding box area
      await downloadCellsInArea(boundingBox);
      List<Point> points = await getPointsInBoundingBox(boundingBox);

      if (points.length < k) {
        debugPrint('Found ${points.length} points < $k');
        bufferMeters *= sqrt2;  // Increase search radius
        if (bufferMeters > metersPerDegree) {
          break;
        }
        continue;
      }

      debugPrint('Found ${points.length} points > $k');
      list.addAll(points);
    }

    Random random = Random();
    return list[random.nextInt(list.length)];
  }

  Future<BoundingBox> createBufferBoundingBox(double lon, double lat, double bufferMeters) async {
    // Fix the latitude buffer calculation
    double latBuffer = bufferMeters / metersPerDegree;
    // Fix the longitude buffer calculation using the center latitude
    double lonBuffer = bufferMeters / (metersPerDegree * cos(lat * pi / 180));

    return BoundingBox(
      lon - lonBuffer,
      lon + lonBuffer,
      lat - latBuffer,
      lat + latBuffer,
    );
  }

  Future<List<Point>> downloadPointsFromServer(BoundingBox boundingBox) async {
    List<Point> downloadedPoints = [];
    try {
      // Using http instead of https since port 5000 might not be configured for SSL
      final uri = Uri.https('snf-78417.ok-kno.grnetcloud.net', '/api/points', {
        'minLon': boundingBox.minLon.toStringAsFixed(6),
        'minLat': boundingBox.minLat.toStringAsFixed(6),
        'maxLon': boundingBox.maxLon.toStringAsFixed(6),
        'maxLat': boundingBox.maxLat.toStringAsFixed(6),
      });
      debugPrint('Downloading points from server: $uri');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timed out');
        },
      );
      
      if (response.statusCode != 200) {
        throw HttpException('Failed with status: ${response.statusCode}');
      }
      
      final document = jsonDecode(response.body);
      final jsonPoints = document['points'].map((node) {
        return {'lon': node['longitude'] as double, 'lat': node['latitude'] as double};
      }).toList();
      debugPrint('Got ${jsonPoints.length} points');

      if (jsonPoints.isEmpty) return [];

      jts.GeometryFactory gf = jts.GeometryFactory.defaultPrecision();
      final values = jsonPoints.map((p) => "(?)").join(",");
      final arguments = jsonPoints.map((p) {
        downloadedPoints.add(Point(p['lon']!, p['lat']!));
        jts.Point point = gf.createPoint(jts.Coordinate(p['lon']!, p['lat']!));
        return GeoPkgGeomWriter().write(point);
      }).toList();
      
      if (arguments.isNotEmpty) {
        db.execute(
          "INSERT OR IGNORE INTO ${pois.fixedName} (geopoint) VALUES $values",
          arguments: arguments
        );
      }

      return downloadedPoints;
    } catch (e) {
      debugPrint('Error downloading points: $e');
      return [];
    }
  }

  Future<List<Point>> downloadPointsFromOSM(BoundingBox boundingBox) async {
    List<Point> downloadedPoints = [];
    final uri = Uri.https('overpass-api.de', '/api/interpreter', {
      'data': '[out:json];'
      'node(${boundingBox.minLat.toStringAsFixed(6)},'
      '${boundingBox.minLon.toStringAsFixed(6)},'
      '${boundingBox.maxLat.toStringAsFixed(6)},'
      '${boundingBox.maxLon.toStringAsFixed(6)});'
      'out;'
    });
    debugPrint('Downloading points from OSM: $uri');
    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timed out');
        },
      );

      if (response.statusCode == 200) {
        final jsonPoints = await compute(parsePointsFromJSON, response.body);
        debugPrint('Got ${jsonPoints.length} points');

        if (jsonPoints.isEmpty) return [];

        jts.GeometryFactory gf = jts.GeometryFactory.defaultPrecision();
        final values = jsonPoints.map((p) => "(?)").join(",");
        final arguments = jsonPoints.map((p) {
          downloadedPoints.add(Point(p['lon']!, p['lat']!));
          jts.Point point = gf.createPoint(jts.Coordinate(p['lon']!, p['lat']!));
          return GeoPkgGeomWriter().write(point);
        }).toList();
        
        if (arguments.isNotEmpty) {
          db.execute(
            "INSERT OR IGNORE INTO ${pois.fixedName} (geopoint) VALUES $values",
            arguments: arguments
          );
        }
      } else {
        debugPrint('Failed to download points: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error downloading points: $e');
    }
    return downloadedPoints;
  }

  Future<List<Point>> getClustersBetweenTwoPoints(Point point1, Point point2, int clusters) async {
    try {
      final uri = Uri.https('snf-78417.ok-kno.grnetcloud.net', '/api/two-point-clusters', {
        'lon1': point1.lon.toStringAsFixed(6),
        'lat1': point1.lat.toStringAsFixed(6),
        'lon2': point2.lon.toStringAsFixed(6),
        'lat2': point2.lat.toStringAsFixed(6),
        'clusters': clusters.toString(),
      });
      debugPrint('Downloading clusters between two points: $uri');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timed out');
        },
      );

      if (response.statusCode != 200) {
        throw HttpException('Failed with status: ${response.statusCode}');
      }
      
      final data = jsonDecode(response.body);
      return data['clusters'].map<Point>((cluster) {
        return Point(
          cluster['longitude'],
          cluster['latitude'],
        );
      }).toList();
    } catch (e) {
      debugPrint('Error getting clusters: $e');
      return [];
    }
  }
}

List<Map<String, double>> parsePointsFromJSON(String jsonString){
  final document = jsonDecode(jsonString);
  return document['elements'].map((node) {
    if (node['type'] == 'node') {
      return {'lon': node['lon'] as double, 'lat': node['lat'] as double};
    }
    return null;
  }).whereType<Map<String, double>>().toList();
}