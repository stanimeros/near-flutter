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

def get_clusters_from_cache(lon1, lat1, lon2, lat2, grid_size):
    cache_key = f"clusters:{lon1}:{lat1}:{lon2}:{lat2}:{grid_size}"
    cached_data = cache.get(cache_key)
    return cached_data if cached_data else None

def add_clusters_to_cache(lon1, lat1, lon2, lat2, grid_size, clusters):
    cache_key = f"clusters:{lon1}:{lat1}:{lon2}:{lat2}:{grid_size}"
    cache.set(cache_key, clusters, timeout=3600)  # Cache for 1 hour

@app.route('/api/cache_clusters', methods=['GET'])
def cache_clusters():
    conn = None
    try:
        # Get parameters
        lon1 = float(request.args.get('lon1'))
        lat1 = float(request.args.get('lat1'))
        lon2 = float(request.args.get('lon2'))
        lat2 = float(request.args.get('lat2'))
        eps = float(request.args.get('eps', 0.00025))
        min_points = int(request.args.get('minPoints', 2))
        grid_size = float(request.args.get('gridSize', 0.01))

        logging.info(f"Cache Clusters called with: lon1={lon1}, lat1={lat1}, lon2={lon2}, lat2={lat2}, eps={eps}, minPoints={min_points}, gridSize={grid_size}")

        # 1. Check cache first
        cached_clusters = get_clusters_from_cache(lon1, lat1, lon2, lat2, grid_size)
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
        if saved_clusters:
            logging.info("Found clusters in saved_clusters table.")
            # Add to cache before returning
            add_clusters_to_cache(lon1, lat1, lon2, lat2, grid_size, saved_clusters)
            return jsonify({'count': len(saved_clusters), 'clusters': saved_clusters, 'source': 'saved_clusters'})

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
            result AS (
                SELECT 
                    grid_x, grid_y,
                    CASE
                        WHEN COUNT(*) OVER () <= %s THEN id::text
                        ELSE ST_ClusterDBSCAN(geom, eps := %s, minpoints := %s) OVER (PARTITION BY grid_x, grid_y)::text
                    END as cluster_id,
                    geom
                FROM points
            ),
            final AS (
                SELECT 
                    grid_x, grid_y,
                    cluster_id,
                    ST_Centroid(ST_Collect(geom)) as center,
                    COUNT(*) as point_count
                FROM result
                GROUP BY grid_x, grid_y, cluster_id
            )
            SELECT 
                grid_x, grid_y,
                cluster_id,
                ST_X(center) as longitude,
                ST_Y(center) as latitude,
                point_count
            FROM final
            ORDER BY grid_x, grid_y, point_count DESC;
        """, (grid_size, grid_size, lon1, lat1, lon2, lat2, min_points, eps, min_points))

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
            add_clusters_to_cache(lon1, lat1, lon2, lat2, grid_size, results)

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