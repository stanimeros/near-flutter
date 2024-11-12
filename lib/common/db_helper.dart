import 'dart:io';
import 'dart:math';
import 'package:dart_jts/dart_jts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'package:dart_hydrologis_db/dart_hydrologis_db.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:dart_hydrologis_utils/dart_hydrologis_utils.dart';

class DbHelper {

  static late GeopackageDb db;
  static String dbFilename = 'geopoints.gpkg';
  static TableName pois = TableName("pois", schemaSupported: false);
  static TableName keys = TableName("keys", schemaSupported: false);

  // Function to initialize the database
  Future<void> initializeDb() async {
    try{
      ConnectionsHandler ch = ConnectionsHandler();
      Directory directory = await getApplicationDocumentsDirectory();
      String dbPath = '${directory.path}/$dbFilename';
      db = ch.open(dbPath);
      db = GeopackageDb.memory();
      db.openOrCreate();
      db.forceRasterMobileCompatibility = false;
      debugPrint('Database ready');
    }catch(e){
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

  Future<void> createSpatialTable(TableName table) async {
    try {
      if (!db.hasTable(table)){
        db.createSpatialTable(
          table,
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
  Future<void> addPointToDb(double lon, double lat, TableName table) async{
    GeometryFactory gf = GeometryFactory.defaultPrecision();
    Point point = gf.createPoint(Coordinate(lon, lat));
    List<int> geomBytes = GeoPkgGeomWriter().write(point);

    String sql = "INSERT OR IGNORE INTO ${table.fixedName} (geopoint) VALUES (?);";
    db.execute(sql, arguments: [geomBytes]);
  }

  // Function to get points within a bounding box
  Future<List<Point>> getPointsInBoundingBox(Envelope boundingBox, TableName table) async{
    List<Point> list = [];

    DateTime before = DateTime.now();
    List<Geometry?> geometries = db.getGeometriesIn(
      table, 
      envelope: boundingBox
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
      List<Point> points = await getPointsInBoundingBox(boundingBox, pois);

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
          await addPointToDb(point['lon']!, point['lat']!, pois);
        }
        debugPrint('Inserted ${await getRowCount(pois)} points');
      }
    } else {
      debugPrint('Failed to download the file. Status code: ${response.statusCode}');
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
}