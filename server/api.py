from gevent import monkey  # type: ignore
monkey.patch_all()  # Add this at the very top of the file, before other imports

import ssl 
import json
import logging
import multiprocessing
from flask import Flask, request, jsonify # type: ignore
from flask_caching import Cache # type: ignore
from psycopg2.extras import RealDictCursor # type: ignore
from gevent.pywsgi import WSGIServer # type: ignore
from psycopg2.pool import ThreadedConnectionPool  #type: ignore
from math import floor

app = Flask(__name__)
app.config['DEBUG'] = True

app.config['CACHE_TYPE'] = 'simple'
cache = Cache(app)

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

@app.route('/api/points', methods=['GET'])
def get_points_in_bbox():
    conn = None
    try:
        # Get parameters from query string
        min_lon = float(request.args.get('minLon'))
        min_lat = float(request.args.get('minLat'))
        max_lon = float(request.args.get('maxLon'))
        max_lat = float(request.args.get('maxLat'))
        
        # Get connection from pool
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        # cur.execute("SET enable_seqscan = off")
    
        # Query points within bbox
        cur.execute("""
            SELECT id, 
                ST_X(geom) as longitude,
                ST_Y(geom) as latitude
            FROM osm_points
            WHERE geom && ST_MakeEnvelope(%s, %s, %s, %s, 4326)
        """, (min_lon, min_lat, max_lon, max_lat))
        
        points = cur.fetchall()
        cur.close()
        
        return jsonify({
            'count': len(points),
            'points': points
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 400
    finally:
        if conn:
            return_db_connection(conn)  # Return connection to pool

def round_coord(coord, precision=4):
    """Round coordinates to reduce variations"""
    return round(coord, precision)

def normalize_bbox(lon1, lat1, lon2, lat2, precision=4):
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

def get_containing_cell(lon, lat, grid_size=0.1):  # Increased grid size
    """Get the larger grid cell that contains this point"""
    return (floor(lon/grid_size), floor(lat/grid_size))

def get_overlapping_cells(lon1, lat1, lon2, lat2, grid_size=0.1):
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

def get_clusters_from_cache(lon1, lat1, lon2, lat2, eps, min_points):
    """New cache function that checks overlapping grid cells"""
    cells = get_overlapping_cells(lon1, lat1, lon2, lat2)
    
    all_clusters = []
    for cell in cells:
        cache_key = f"clusters:cell_{cell[0]}_{cell[1]}:eps_{eps}:min_{min_points}"
        cell_clusters = cache.get(cache_key)
        if cell_clusters:
            all_clusters.extend(cell_clusters)
    
    if all_clusters:
        # Filter clusters to only include those within the requested bbox
        filtered_clusters = [
            cluster for cluster in all_clusters
            if (lon1 <= cluster['longitude'] <= lon2 and
                lat1 <= cluster['latitude'] <= lat2)
        ]
        if filtered_clusters:
            return filtered_clusters
    
    return None

def add_clusters_to_cache(lon1, lat1, lon2, lat2, eps, min_points, clusters):
    """Store clusters in their respective grid cells"""
    cells = get_overlapping_cells(lon1, lat1, lon2, lat2)
    
    for cell in cells:
        # Filter clusters for this cell
        cell_min_lon = cell[0] * 0.1
        cell_max_lon = (cell[0] + 1) * 0.1
        cell_min_lat = cell[1] * 0.1
        cell_max_lat = (cell[1] + 1) * 0.1
        
        cell_clusters = [
            cluster for cluster in clusters
            if (cell_min_lon <= cluster['longitude'] <= cell_max_lon and
                cell_min_lat <= cluster['latitude'] <= cell_max_lat)
        ]
        
        if cell_clusters:
            cache_key = f"clusters:cell_{cell[0]}_{cell[1]}:eps_{eps}:min_{min_points}"
            cache.set(cache_key, cell_clusters, timeout=7200)  # Cache for 2 hours

@app.route('/api/clusters', methods=['GET'])
def cache_clusters():
    conn = None
    try:
        # Get and validate parameters
        try:
            lon1 = float(request.args.get('lon1'))
            lat1 = float(request.args.get('lat1'))
            lon2 = float(request.args.get('lon2'))
            lat2 = float(request.args.get('lat2'))
            eps = 0.0002  # Fixed eps
            min_points = 16  # Fixed min_points
            grid_size = 0.1  # Larger grid size
            
            # Normalize coordinates
            lon1, lat1, lon2, lat2 = normalize_bbox(lon1, lat1, lon2, lat2)
            
            # Rest of the validation...
            if not (-180 <= lon1 <= 180 and -180 <= lon2 <= 180):
                raise ValueError("Longitude must be between -180 and 180")
            if not (-90 <= lat1 <= 90 and -90 <= lat2 <= 90):
                raise ValueError("Latitude must be between -90 and 90")
                
        except ValueError as e:
            return jsonify({'error': str(e)}), 400

        logging.info(f"Cache Clusters called with: lon1={lon1}, lat1={lat1}, lon2={lon2}, lat2={lat2}, eps={eps}, minPoints={min_points}, gridSize={grid_size}")

        # 1. Check cache first
        cached_clusters = get_clusters_from_cache(lon1, lat1, lon2, lat2, eps, min_points)
        if cached_clusters:
            logging.info("Returning cached clusters.")
            return jsonify({'count': len(cached_clusters), 'clusters': cached_clusters, 'source': 'cache'})

        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)

        # 2. Check saved clusters table
        cur.execute("""
            SELECT * FROM saved_clusters 
            WHERE bbox && ST_MakeEnvelope(%s, %s, %s, %s, 4326)
            AND eps = %s AND min_points = %s AND grid_size = %s
        """, (lon1, lat1, lon2, lat2, eps, min_points, grid_size))
        
        saved_clusters = cur.fetchall()
        if saved_clusters and saved_clusters[0].get('clusters'):
            logging.info("Found clusters in saved_clusters table.")
            clusters_data = saved_clusters[0]['clusters']
            if isinstance(clusters_data, str):
                clusters_data = json.loads(clusters_data)
            # Add to cache before returning
            add_clusters_to_cache(lon1, lat1, lon2, lat2, eps, min_points, clusters_data)
            return jsonify({'count': len(clusters_data), 'clusters': clusters_data, 'source': 'saved_clusters'})

        # 3. Perform clustering from database
        logging.info("Performing new clustering...")
        cur.execute("""
            WITH points AS (
                SELECT id, geom,
                    FLOOR(ST_X(geom) / %s) AS grid_x,
                    FLOOR(ST_Y(geom) / %s) AS grid_y
                FROM osm_points
                WHERE geom && ST_MakeEnvelope(%s, %s, %s, %s, 4326)
            ),
            clustered AS (
                SELECT 
                    grid_x, grid_y,
                    ST_ClusterDBSCAN(geom, eps := %s, minpoints := %s) OVER (PARTITION BY grid_x, grid_y) as cluster_id,
                    geom
                FROM points
            ),
            final AS (
                SELECT 
                    grid_x, grid_y,
                    CASE 
                        WHEN cluster_id IS NULL THEN 'noise'
                        ELSE cluster_id::text 
                    END as cluster_id,
                    ST_Centroid(ST_Collect(geom)) as center,
                    COUNT(*) as point_count
                FROM clustered
                GROUP BY grid_x, grid_y, cluster_id
            )
            SELECT 
                grid_x, grid_y,
                cluster_id,
                ST_X(center) as longitude,
                ST_Y(center) as latitude,
                point_count
            FROM final
            ORDER BY point_count DESC;    -- Order by size, largest first
        """, (grid_size, grid_size, lon1, lat1, lon2, lat2, eps, min_points))

        results = cur.fetchall()
        
        if results:
            # Store results in saved_clusters table
            cur.execute("""
                INSERT INTO saved_clusters (
                    bbox, eps, min_points, grid_size, clusters, created_at
                ) VALUES (
                    ST_MakeEnvelope(%s, %s, %s, %s, 4326),
                    %s, %s, %s, %s, NOW()
                )
            """, (lon1, lat1, lon2, lat2, eps, min_points, grid_size, json.dumps(results)))
            
            conn.commit()
            
            # Add to cache
            add_clusters_to_cache(lon1, lat1, lon2, lat2, eps, min_points, results)

        logging.info(f"Query returned {len(results)} clusters across {len(set((r['grid_x'], r['grid_y']) for r in results))} grid cells.")

        return jsonify({
            'count': len(results),
            'clusters': results,
            'source': 'new_clustering'
        })

    except Exception as e:
        logging.error(f"Error in cache_clusters: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500

    finally:
        if conn:
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