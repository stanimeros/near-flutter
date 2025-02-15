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
  static const double gridSize = 0.005;
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
          "cell_min_lon INTEGER, cell_min_lat INTEGER",
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

  Future<void> addCellToDb(int minLon, int minLat) async {
    String sql = "INSERT OR IGNORE INTO ${cells.fixedName} (cell_min_lon, cell_min_lat) VALUES (?, ?);";
    db.execute(sql, arguments: [minLon, minLat]);
  }

  Future<List<BoundingBox>> getCellsInArea(BoundingBox boundingBox) async {
    List<BoundingBox> cellsInArea = [];
    try {
      int minLon = (boundingBox.minLon / gridSize).floor();
      int maxLon = (boundingBox.maxLon / gridSize).floor();
      int minLat = (boundingBox.minLat / gridSize).floor();
      int maxLat = (boundingBox.maxLat / gridSize).floor();
      
      final existingCells = db.select(
        'SELECT cell_min_lon, cell_min_lat FROM ${cells.fixedName} WHERE cell_min_lon BETWEEN $minLon AND $maxLon AND cell_min_lat BETWEEN $minLat AND $maxLat'
      );

      existingCells.forEach(
        (row) async {
          final cell = await createBufferBoundingBox(
            row.get("cell_min_lon") * gridSize,
            row.get("cell_min_lat") * gridSize,
            gridSize
          );
          cellsInArea.add(cell);
        }
      );

      for (int lon = minLon; lon <= maxLon; lon++) {
        for (int lat = minLat; lat <= maxLat; lat++) {
          final cell = await createBufferBoundingBox(
            lon * gridSize, 
            lat * gridSize, 
            gridSize
          );
          
          if (!cellsInArea.contains(cell)) {
            await addCellToDb(lon, lat);
            cellsInArea.add(cell);
            downloadPointsFromOSM(cell);
          }
        }
      }

      return cellsInArea;
    }catch(e){
      debugPrint(e.toString());
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
      await getCellsInArea(boundingBox);
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

  Future<void> downloadPointsFromOSM(BoundingBox boundingBox) async {
    String api = 'https://overpass-api.de/api/interpreter?data=[out:json];'
      'node(${boundingBox.minLat},${boundingBox.minLon},${boundingBox.maxLat},${boundingBox.maxLon});'
      'out;';

    debugPrint('Downloading from: $api');
    final response = await http.get(
      Uri.parse(api),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      debugPrint('Parsing points');
      final points = await compute(parsePointsFromJSON, response.body);

      debugPrint('Got ${points.length} points');
      if (points.isEmpty) return;
      jts.GeometryFactory gf = jts.GeometryFactory.defaultPrecision();

      try {
        // Build values string for all points
        final values = points.map((p) => "(?)").join(",");
        final arguments = points.map((p) {
          jts.Point point = gf.createPoint(jts.Coordinate(p['lon']!, p['lat']!));
          List<int> geomBytes = GeoPkgGeomWriter().write(point);
          return geomBytes;
        }).toList();
        
        // Execute single insert with all points
        db.execute(
          "INSERT OR IGNORE INTO ${pois.fixedName} (geopoint) VALUES $values",
          arguments: arguments
        );
      } catch (e) {
        debugPrint(e.toString());
      }
    } else {
      debugPrint('Failed to download points: ${response.body}');
      throw Exception('Failed to download points: ${response.statusCode}');
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