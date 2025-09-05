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
import 'package:flutter/services.dart' show rootBundle;

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
  static TableName cells = TableName("cells_pois", schemaSupported: false);
  
  // Function to initialize the database
  Future<void> openDbFile(String dbFilename) async {
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

  Future<void> deleteDbFile(String dbFilename) async {
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

  Future<void> createSpatialTable(TableName poisTable) async {
    try {
      if (!db.hasTable(poisTable)){
        db.createSpatialTable(
          poisTable,
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

  Future<void> createCellsTable(TableName cellsTable) async {
    try {
      if (!db.hasTable(cellsTable)) {
        db.createSpatialTable(
          cellsTable,
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

  Future<void> addCellToTable(GridCell cell, TableName cellsTable) async {
    String sql = "INSERT OR IGNORE INTO ${cellsTable.fixedName} (cell_lon, cell_lat) VALUES (?, ?);";
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
      if (totalCells > 100) {
        debugPrint('Too many cells: $totalCells > 100');
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

  Future<List<BoundingBox>> downloadCellsInArea(BoundingBox boundingBox, TableName poisTable, TableName cellsTable) async {
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
        'SELECT cell_lon, cell_lat FROM ${cellsTable.fixedName} WHERE cell_lon BETWEEN $minLonCell AND $maxLonCell AND cell_lat BETWEEN $minLatCell AND $maxLatCell'
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

      if (cellsToDownload > 100) {
        debugPrint('Too many cells to download: $cellsToDownload > 100');
        return [];
      }

      // Process each cell in the grid
      for (GridCell cell in gridCells) {
        final cellKey = cell.getKey();

        if (!existingSet.contains(cellKey)) {
          debugPrint('Downloading new cell $cellKey: ${cell.lon},${cell.lat}');
          await addCellToTable(cell, cellsTable);
          BoundingBox boundingBox = BoundingBox(cell.lon * gridSize, (cell.lon + 1) * gridSize, cell.lat * gridSize, (cell.lat + 1) * gridSize);
          List<Point> points = await downloadPointsFromServer(boundingBox, poisTable);
          if (points.isEmpty) {
            points = await downloadPointsFromOSM(boundingBox, poisTable);
          }
          // Add small delay to avoid overwhelming the server
          await Future.delayed(Duration(milliseconds: 1000));
          //TODO: Remove the delay later
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
  Future<List<Point>> getPointsInBoundingBox(BoundingBox boundingBox, TableName poisTable) async {
    List<Point> list = [];
    DateTime before = DateTime.now();
    List<jts.Geometry?> geometries = db.getGeometriesIn(
      poisTable, envelope: boundingBox.envelope
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

  Future<List<Point>> getKNNs(int k, double lon, double lat, double bufferMeters, TableName poisTable, TableName cellsTable) async {
    List<Point> list = [];

    while (list.length < k) {
      debugPrint('Creating bbox with side ${bufferMeters*2}m');
      BoundingBox boundingBox = await createBufferBoundingBox(lon, lat, bufferMeters);

      await downloadCellsInArea(boundingBox, poisTable, cellsTable);
      List<Point> points = await getPointsInBoundingBox(boundingBox, poisTable);

      if (points.length < k) {
        debugPrint('Found ${points.length} points < $k');
        bufferMeters *= sqrt2;  // Increase search radius
        if (bufferMeters > 50000) { // Limit to 50km radius (reasonable for urban areas)
          debugPrint('Reached maximum search radius of 50km');
          break;
        }
        continue;
      }

      debugPrint('Found ${points.length} points > $k');
      list.addAll(points);
    }

    return list;
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

  Future<List<Point>> downloadPointsFromServer(BoundingBox boundingBox, TableName poisTable) async {
    List<Point> downloadedPoints = [];
    try {
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
      downloadedPoints = (document['points'] as List).map((node) {
        return Point(
          node['longitude'] as double, 
          node['latitude'] as double,
          // Optionally store the id if needed
          // id: node['id'] as int,
        );
      }).toList();
      
      if (downloadedPoints.isNotEmpty) {
        debugPrint('Adding ${downloadedPoints.length} points to ${poisTable.fixedName}');
        await addPointsToTable(downloadedPoints, poisTable);
      }

      return downloadedPoints;
    } catch (e) {
      debugPrint('Error downloading points: $e');
      return [];
    }
  }

  Future<List<Point>> downloadPointsFromOSM(BoundingBox boundingBox, TableName poisTable) async {
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
        downloadedPoints = await compute(parsePointsFromJSON, response.body);

        if (downloadedPoints.isNotEmpty) {
          debugPrint('Adding ${downloadedPoints.length} points to ${poisTable.fixedName}');
          await addPointsToTable(downloadedPoints, poisTable);
        }
      } else {
        debugPrint('Failed to download points: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error downloading points: $e');
    }
    return downloadedPoints;
  }

  Future<List<Point>> getClustersBetweenTwoPoints(Point point1, Point point2, {method = 'dbscan', int clusters = 20, double eps = 0.00025, int minPoints = 2, http.Client? httpClient}) async {
    try {
      final uri = Uri.https('snf-78417.ok-kno.grnetcloud.net', '/api/clusters', {
        'lon1': point1.lon.toStringAsFixed(6),
        'lat1': point1.lat.toStringAsFixed(6),
        'lon2': point2.lon.toStringAsFixed(6),
        'lat2': point2.lat.toStringAsFixed(6),
      });
      
      http.Response response;
      debugPrint('Downloading clusters between two points: $uri');
      if (httpClient == null) {
        response = await http.get(uri).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Request timed out');
          },
        );
      } else {
        response = await httpClient.get(uri).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Request timed out');
          },
        );
      }

      if (response.statusCode != 200) {
        throw HttpException('Failed with status: ${response.statusCode}');
      }
      
      final data = jsonDecode(response.body);
      List<Point> allClusters = [];
      
      // Process clusters from all cities
      if (data['cities'] != null) {
        for (var city in data['cities']) {
          for (var cluster in city['clusters']) {
            allClusters.add(Point(
              cluster['longitude'],
              cluster['latitude'],
            ));
          }
        }
      }
      
      debugPrint('Found ${allClusters.length} clusters across all cities');
      return allClusters;
    } catch (e) {
      debugPrint('Error getting clusters: $e');
      return [];
    }
  }

  // New method to get city polygons within the map view
  Future<List<Map<String, dynamic>>> getCitiesInBoundingBox(BoundingBox boundingBox, {http.Client? httpClient}) async {
    try {
      final uri = Uri.https('snf-78417.ok-kno.grnetcloud.net', '/api/cities', {
        'minLon': boundingBox.minLon.toStringAsFixed(6),
        'minLat': boundingBox.minLat.toStringAsFixed(6),
        'maxLon': boundingBox.maxLon.toStringAsFixed(6),
        'maxLat': boundingBox.maxLat.toStringAsFixed(6),
      });
      
      http.Response response;
      debugPrint('Downloading city polygons: $uri');
      if (httpClient == null) {
        response = await http.get(uri).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Request timed out');
          },
        );
      } else {
        response = await httpClient.get(uri).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Request timed out');
          },
        );
      }

      if (response.statusCode != 200) {
        throw HttpException('Failed with status: ${response.statusCode}');
      }
      
      final data = jsonDecode(response.body);
      List<Map<String, dynamic>> cities = [];
      
      if (data['cities'] != null) {
        for (var city in data['cities']) {
          cities.add({
            'id': city['id'],
            'name': city['name'],
            'geometry': jsonDecode(city['geometry']),
          });
        }
      }
      
      debugPrint('Found ${cities.length} cities in the bounding box');
      return cities;
    } catch (e) {
      debugPrint('Error getting city polygons: $e');
      return [];
    }
  }

  Future<void> addPointsToTable(List<Point> points, TableName poisTable) async {
    jts.GeometryFactory gf = jts.GeometryFactory.defaultPrecision();
    final values = points.map((p) => "(?)").join(",");
    final arguments = points.map((p) {
      jts.Point point = gf.createPoint(jts.Coordinate(p.lon, p.lat));
      return GeoPkgGeomWriter().write(point);
    }).toList();

    if (arguments.isNotEmpty) {
      db.execute(
        "INSERT OR IGNORE INTO ${poisTable.fixedName} (geopoint) VALUES $values",
        arguments: arguments
      );
    }
  }   

  Future<void> importPointsFromAsset(String assetPath, TableName poisTable) async {
    debugPrint('Importing points from $assetPath to ${poisTable.fixedName}');

    int pointsImported = 0;
    const batchSize = 1000;
    List<String> currentBatch = [];
    
    // Get the asset file as a string stream
    final ByteData data = await rootBundle.load(assetPath);
    final String contents = utf8.decode(data.buffer.asUint8List());
    final Stream<String> lines = Stream.fromIterable(contents.split('\n'));
    
    await for (final line in lines) {
      if (line.isNotEmpty) {
        currentBatch.add(line);
      }
      
      // Process batch when it reaches 1000 lines
      if (currentBatch.length >= batchSize) {
        final batchPoints = currentBatch.map((line) {
          final parts = line.split('-');
          final lon = double.parse(parts[0]);
          final lat = double.parse(parts[1]);
          return Point(lon, lat);
        }).toList();
        await addPointsToTable(batchPoints, poisTable);
        pointsImported += batchPoints.length;
        currentBatch = []; // Clear the batch
      }
    }
    
    // Process any remaining lines
    if (currentBatch.isNotEmpty) {
      final batchPoints = currentBatch.map((line) {
        final parts = line.split('-');
        final lon = double.parse(parts[0]);
        final lat = double.parse(parts[1]);
        return Point(lon, lat);
      }).toList();
      await addPointsToTable(batchPoints, poisTable);
      pointsImported += batchPoints.length;
    }

    debugPrint('Imported $pointsImported points');
  }
}

List<Point> parsePointsFromJSON(String jsonString){
  final document = jsonDecode(jsonString);
  return document['elements'].map((node) {
    if (node['type'] == 'node') {
      return Point(node['lon'] as double, node['lat'] as double);
    }
    return null;
  }).whereType<Map<String, double>>().toList();
}