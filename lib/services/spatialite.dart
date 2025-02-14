import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dart_jts/dart_jts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'package:dart_hydrologis_db/dart_hydrologis_db.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class Spatialite {
  static late GeopackageDb db;
  static const double gridSize = 0.0025;
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

  Future<void> deleteDb() async {
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
          "cell_x INTEGER, cell_y INTEGER",
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

  Future<void> addCellToDb(int x, int y) async {
    String sql = "INSERT OR IGNORE INTO ${cells.fixedName} (cell_x, cell_y) VALUES (?, ?);";
    db.execute(sql, arguments: [x, y]);
  }

  Future<void> ensureCellsInArea(Envelope boundingBox) async {
    try {
      int minX = (boundingBox.getMinX() / gridSize).floor();
      int maxX = (boundingBox.getMaxX() / gridSize).floor();
      int minY = (boundingBox.getMinY() / gridSize).floor();
      int maxY = (boundingBox.getMaxY() / gridSize).floor();

      debugPrint('Grid area: ($minX,$minY) to ($maxX,$maxY) - ${(maxX-minX)*(maxY-minY)} cells');

      // Get existing cells first
      final existingCells = db.select(
        'SELECT cell_x, cell_y FROM ${cells.fixedName} WHERE cell_x BETWEEN $minX AND $maxX AND cell_y BETWEEN $minY AND $maxY'
      );
      
      // Fix: Create set properly
      final existingSet = <String>{};
      existingCells.forEach(
        (row) => existingSet.add('${row.get("cell_x")},${row.get("cell_y")}')
      );

      debugPrint('Found ${existingSet.length} existing cells');

      // Download missing cells with rate limiting
      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          final cellKey = '$x,$y';
          if (!existingSet.contains(cellKey)) {
            debugPrint('Need to download cell $cellKey');
            double cellMinLon = x * gridSize;
            double cellMaxLon = (x + 1) * gridSize;
            double cellMinLat = y * gridSize;
            double cellMaxLat = (y + 1) * gridSize;

            await downloadPointsFromOSM(cellMinLon, cellMinLat, cellMaxLon, cellMaxLat);
            await addCellToDb(x, y);
          }
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // Function to get points within a bounding box
  Future<List<Point>> getPointsInBoundingBox(Envelope boundingBox) async {
    await ensureCellsInArea(boundingBox);

    List<Point> list = [];
    DateTime before = DateTime.now();
    List<Geometry?> geometries = db.getGeometriesIn(
      pois, envelope: boundingBox
    );
    DateTime after = DateTime.now();
    debugPrint('Query took ${after.difference(before).inMilliseconds.toString()}ms');

    for (var geometry in geometries) {
      if (geometry is Point) {
        list.add(geometry);
      }
    }
    return list;
  }

  Future<Point> getRandomKNN(int k, double lon, double lat, double bufferMeters) async {
    List<Point> list = [];

    while (list.length < k){
      debugPrint('Creating bbox with side ${bufferMeters*2}m');
      Envelope boundingBox = await createBoundingBox(lon, lat, bufferMeters);
      List<Point> points = await getPointsInBoundingBox(boundingBox);

      if (points.length < k){
        debugPrint('Found ${points.length} points < $k');
        bufferMeters *= sqrt2;
        if (bufferMeters > 111000.0){
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

  Future<Envelope> createBoundingBox(double lon, double lat, double bufferMeters) async{
    const double metersPerDegree = 111000.0;
    double latBuffer = bufferMeters / metersPerDegree;
    double lonBuffer = bufferMeters / (metersPerDegree * cos(lat * pi / 180));

    Envelope boundingBox = Envelope(
      lon - lonBuffer,
      lon + lonBuffer,
      lat - latBuffer,
      lat + latBuffer,
    );

    return boundingBox;
  }

  Future<void> downloadPointsFromOSM(double minLon, double minLat, double maxLon, double maxLat) async {
    String api = 'https://overpass-api.de/api/interpreter?data=[out:json];'
      'node($minLat,$minLon,$maxLat,$maxLon);'
      'out;';
    
    debugPrint('Downloading from: $api');
    final response = await http.get(
      Uri.parse(api),
    ).timeout(const Duration(milliseconds: 5000));

    if (response.statusCode == 200) {
      debugPrint('Parsing points');
      final points = await compute(parsePointsFromJSON, response.body);

      debugPrint('Got ${points.length} points');
      GeometryFactory gf = GeometryFactory.defaultPrecision();

      try {
        // Build values string for all points
        final values = points.map((p) => "(?)").join(",");
        final arguments = points.map((p) {
          Point point = gf.createPoint(Coordinate(p['lon']!, p['lat']!));
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