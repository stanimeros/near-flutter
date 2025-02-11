import 'dart:io';
import 'dart:math';
import 'package:dart_jts/dart_jts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'package:dart_hydrologis_db/dart_hydrologis_db.dart';
import 'package:flutter_near/services/osm_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dart_hydrologis_utils/dart_hydrologis_utils.dart';

class DbHelper {

  static late GeopackageDb db;
  static String dbFilename = 'geopoints.gpkg';
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
  Future<List<Point>> getPointsInBoundingBox(Envelope boundingBox) async {
    await OSMService().ensurePointsInArea(boundingBox);

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
}