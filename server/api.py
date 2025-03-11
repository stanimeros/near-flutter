from gevent import monkey  # type: ignore
monkey.patch_all()  # Add this at the very top of the file, before other imports

import ssl
import logging
import multiprocessing
from flask import Flask, request, jsonify  # type: ignore
from flask_caching import Cache  # type: ignore
from psycopg2.extras import RealDictCursor  # type: ignore
from gevent.pywsgi import WSGIServer  # type: ignore
from psycopg2.pool import ThreadedConnectionPool  # type: ignore
from math import floor

app = Flask(__name__)
app.config['DEBUG'] = True
cache = Cache(app, config={'CACHE_TYPE': 'simple'})

# Configure logging
logging.basicConfig(level=logging.DEBUG, filename='app.log', filemode='a',
                    format='%(asctime)s - %(levelname)s - %(message)s')

# Create a global connection pool
db_pool = ThreadedConnectionPool(
    minconn=10,      # Minimum number of connections
    maxconn=100,     # Maximum number of connections
    dsn="dbname=osm_points user=postgres"
)

# Replace get_db_connection with pool-based version
def get_db_connection():
    return db_pool.getconn()

def return_db_connection(conn):
    db_pool.putconn(conn)

@app.route('/favicon.ico')
def favicon():
    return '', 204

def round_coord(coord, precision):
    """Round coordinates to reduce variations"""
    return round(coord, precision)

def normalize_bbox(lon1, lat1, lon2, lat2, precision):
    """Normalize bbox coordinates to increase cache hits"""
    # Round coordinates
    lon1 = round_coord(lon1, precision)
    lat1 = round_coord(lat1, precision)
    lon2 = round_coord(lon2, precision)
    lat2 = round_coord(lat2, precision)
    
    # Ensure correct order (min to max)
    min_lon = min(lon1, lon2)
    max_lon = max(lon1, lon2)
    min_lat = min(lat1, lat2)
    max_lat = max(lat1, lat2)
    
    return min_lon, min_lat, max_lon, max_lat

def get_containing_cell(lon, lat, grid_size):  # Increased grid size
    """Get the larger grid cell that contains this point"""
    return (floor(lon/grid_size), floor(lat/grid_size))

def get_overlapping_cells(lon1, lat1, lon2, lat2, grid_size):
    """Get all grid cells that overlap with this bbox"""
    min_lon = min(lon1, lon2)
    max_lon = max(lon1, lon2)
    min_lat = min(lat1, lat2)
    max_lat = max(lat1, lat2)
    
    start_cell = get_containing_cell(min_lon, min_lat, grid_size)
    end_cell = get_containing_cell(max_lon, max_lat, grid_size)
    
    cells = []
    for x in range(start_cell[0], end_cell[0] + 1):
        for y in range(start_cell[1], end_cell[1] + 1):
            cells.append((x, y))
    return cells

@app.route('/api/clusters', methods=['GET'])
def cache_clusters():
    conn = None
    cur = None
    try:
        # Get and validate parameters
        try:
            lon1 = float(request.args.get('lon1'))
            lat1 = float(request.args.get('lat1'))
            lon2 = float(request.args.get('lon2'))
            lat2 = float(request.args.get('lat2'))
            # Adjust parameters to be more restrictive
            eps = 0.0001          # About 11 meters (down from 22)
            min_points = 20       # Up from 16
            grid_size = 0.16      # Keep the same grid size
            precision = 4
            
            # Normalize coordinates
            lon1, lat1, lon2, lat2 = normalize_bbox(lon1, lat1, lon2, lat2, precision)
            
            # Validation...
            if not (-180 <= lon1 <= 180 and -180 <= lon2 <= 180):
                raise ValueError("Longitude must be between -180 and 180")
            if not (-90 <= lat1 <= 90 and -90 <= lat2 <= 90):
                raise ValueError("Latitude must be between -90 and 90")
                
        except ValueError as e:
            return jsonify({'error': str(e)}), 400

        logging.info(f"Cache Clusters called with: lon1={lon1}, lat1={lat1}, lon2={lon2}, lat2={lat2}, eps={eps}, minPoints={min_points}, gridSize={grid_size}")

        cells = get_overlapping_cells(lon1, lat1, lon2, lat2, grid_size)
        
        all_clusters = []
        cached_count = 0
        stored_count = 0
        new_count = 0

        cells_to_check_stored = []
        cells_to_generate = []

        # 1. First try cache for all cells
        for cell in cells:
            cache_key = f"cell_{cell[0]}_{cell[1]}_{grid_size}"
            cell_clusters = cache.get(cache_key)
            
            if cell_clusters:
                all_clusters.extend(cell_clusters)
                cached_count += len(cell_clusters)
            else:
                cells_to_check_stored.append(cell)

        # 2. Check stored data for missing cells
        if cells_to_check_stored:
            conn = get_db_connection()
            cur = conn.cursor(cursor_factory=RealDictCursor)

            for cell in cells_to_check_stored:
                min_lon = cell[0] * grid_size
                max_lon = (cell[0] + 1) * grid_size
                min_lat = cell[1] * grid_size
                max_lat = (cell[1] + 1) * grid_size

                # Check stored clusters table
                cur.execute("""
                    SELECT cluster_id, longitude, latitude, point_count 
                    FROM stored_clusters 
                    WHERE cell_x = %s AND cell_y = %s AND grid_size = %s
                """, (cell[0], cell[1], grid_size))
                
                stored_results = cur.fetchall()
                if stored_results:
                    all_clusters.extend(stored_results)
                    stored_count += len(stored_results)
                    # Also cache these results
                    cache_key = f"cell_{cell[0]}_{cell[1]}_{grid_size}"
                    cache.set(cache_key, stored_results, timeout=86400)
                else:
                    cells_to_generate.append(cell)

        # 3. Generate new clusters for remaining cells
        if cells_to_generate:
            if not conn:
                conn = get_db_connection()
                cur = conn.cursor(cursor_factory=RealDictCursor)

            for cell in cells_to_generate:
                min_lon = cell[0] * grid_size
                max_lon = (cell[0] + 1) * grid_size
                min_lat = cell[1] * grid_size
                max_lat = (cell[1] + 1) * grid_size

                # Generate new clusters
                cur.execute("""
                    WITH points AS (
                        SELECT id, geom
                        FROM osm_points
                        WHERE geom && ST_MakeEnvelope(%s, %s, %s, %s, 4326)
                    ),
                    clustered AS (
                        SELECT 
                            ST_ClusterDBSCAN(geom, eps := %s, minpoints := %s) OVER () AS cluster_id,
                            geom
                        FROM points
                    ),
                    final AS (
                        SELECT 
                            cluster_id,
                            ST_Centroid(ST_Collect(geom)) AS center,
                            COUNT(*) AS point_count
                        FROM clustered
                        WHERE cluster_id IS NOT NULL
                        GROUP BY cluster_id
                    )
                    SELECT 
                        cluster_id,
                        ST_X(center) AS longitude,
                        ST_Y(center) AS latitude,
                        point_count
                    FROM final
                    ORDER BY point_count DESC;
                """, (min_lon, min_lat, max_lon, max_lat, eps, min_points))
                
                new_results = cur.fetchall()
                if new_results:
                    all_clusters.extend(new_results)
                    new_count += len(new_results)
                    
                    # Cache the results
                    cache_key = f"cell_{cell[0]}_{cell[1]}_{grid_size}"
                    cache.set(cache_key, new_results, timeout=86400)
                    
                    # Store in database
                    for cluster in new_results:
                        cur.execute("""
                            INSERT INTO stored_clusters 
                            (cluster_id, longitude, latitude, point_count, cell_x, cell_y, grid_size)
                            VALUES (%s, %s, %s, %s, %s, %s, %s)
                        """, (cluster['cluster_id'], cluster['longitude'], 
                              cluster['latitude'], cluster['point_count'],
                              cell[0], cell[1], grid_size))
            
            conn.commit()

        response = {
            'total_count': len(all_clusters),
            'cached_count': cached_count,
            'stored_count': stored_count,
            'new_count': new_count,
            'clusters': all_clusters,
            'bbox': {
                'lon1': lon1, 'lat1': lat1,
                'lon2': lon2, 'lat2': lat2
            },
            'parameters': {
                'eps': eps,
                'min_points': min_points,
                'grid_size': grid_size
            }
        }

        logging.info(f"Returning {len(all_clusters)} total clusters (cached: {cached_count}, stored: {stored_count}, new: {new_count})")
        return jsonify(response)

    except Exception as e:
        if conn and not conn.closed:
            conn.rollback()
        logging.error(f"Error in cache_clusters: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500

    finally:
        if cur:
            cur.close()
        if conn and not conn.closed:
            return_db_connection(conn)

if __name__ == '__main__':
    ssl_cert = '/etc/letsencrypt/live/snf-78417.ok-kno.grnetcloud.net/fullchain.pem'
    ssl_key = '/etc/letsencrypt/live/snf-78417.ok-kno.grnetcloud.net/privkey.pem'
    
    ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ssl_context.load_cert_chain(certfile=ssl_cert, keyfile=ssl_key)

    cpu_cores = multiprocessing.cpu_count()
    optimal_workers = cpu_cores * 2

    http_server = WSGIServer(
        application=app,
        ssl_context=ssl_context,
        listener=('0.0.0.0', 443), 
        spawn=optimal_workers,
    )
    
    print('Starting server with connection pool and multiple workers...')
    http_server.serve_forever()