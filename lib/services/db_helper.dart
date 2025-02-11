import 'dart:io';
import 'dart:math';
import 'package:dart_jts/dart_jts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'package:dart_hydrologis_db/dart_hydrologis_db.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dart_hydrologis_utils/dart_hydrologis_utils.dart';
import 'package:xml/xml.dart';
import 'package:http/http.dart' as http;

class DbHelper {
  static late GeopackageDb db;
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

  Future<void> openDbMemory() async {
    try {
      db = GeopackageDb.memory(); //Will not use the file db
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

  Future<int> getRowCount(TableName table) async{
    try {
      QueryResult select = db.select("SELECT COUNT(*) AS COUNT FROM ${table.fixedName}");
      QueryResultRow firstRow = select.first;
      return firstRow.get("COUNT");
    } catch (e) {
      debugPrint('Error getting row count: $e');
      return 0;
    }
  }

  // Function to add a point to the database
  Future<void> addPointToDb(double lon, double lat) async{
    GeometryFactory gf = GeometryFactory.defaultPrecision();
    Point point = gf.createPoint(Coordinate(lon, lat));
    List<int> geomBytes = GeoPkgGeomWriter().write(point);

    String sql = "INSERT OR IGNORE INTO ${pois.fixedName} (geopoint) VALUES (?);";
    db.execute(sql, arguments: [geomBytes]);
  }

  Future<void> addCellToDb(int x, int y) async {
    String sql = "INSERT OR IGNORE INTO ${cells.fixedName} (cell_x, cell_y) VALUES (?, ?);";
    db.execute(sql, arguments: [x, y]);
  }

  Future<void> ensureCellsInArea(Envelope boundingBox) async {
    // Convert to grid coordinates
    const double gridSize = 0.001;
    int minX = (boundingBox.getMinX() / gridSize).floor();
    int maxX = (boundingBox.getMaxX() / gridSize).floor();
    int minY = (boundingBox.getMinY() / gridSize).floor();
    int maxY = (boundingBox.getMaxY() / gridSize).floor();

    debugPrint('Checking cells from ($minX,$minY) to ($maxX,$maxY)');

    // Get existing cells in area
    List<Geometry?> existingCells = db.getGeometriesIn(
      cells, envelope: boundingBox
    );

    // Download missing cells
    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        bool cellExists = false;
        for (var geom in existingCells) {
          if (geom != null) {
            // Check if this cell matches current coordinates
            Point point = geom as Point;
            if (point.getX() == x && point.getY() == y) {
              cellExists = true;
              break;
            }
          }
        }

        if (!cellExists) {
          debugPrint('Downloading cell ($x,$y)');
          // Calculate cell bounds
          double cellMinLon = x * gridSize;
          double cellMaxLon = (x + 1) * gridSize;
          double cellMinLat = y * gridSize;
          double cellMaxLat = (y + 1) * gridSize;

          await downloadPointsFromOSM(
            cellMinLon, cellMinLat, cellMaxLon, cellMaxLat
          );
          await addCellToDb(x, y);
        }
      }
    }
  }
  
  Future<List<Geometry?>> getCellsInArea(Envelope boundingBox) async {
    await ensureCellsInArea(boundingBox);
    return db.getGeometriesIn(cells, envelope: boundingBox);
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
    String url = 'https://overpass-api.de/api/map?bbox='
      '$minLon,$minLat,$maxLon,$maxLat';  // OSM expects: min_lon,min_lat,max_lon,max_lat
    
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final points = await compute(parsePoints, response.body);
      debugPrint('Downloaded ${points.length} points');

      for (var point in points) {
        await DbHelper().addPointToDb(point['lon']!, point['lat']!);
      } 
    } else {
      debugPrint('Failed request URL: $url');
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