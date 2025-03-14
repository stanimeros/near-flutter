from gevent import monkey  # type: ignore
monkey.patch_all()  # Add this at the very top of the file, before other imports

import ssl 
import uuid
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

db_pool = ThreadedConnectionPool(
    minconn=10,      # Minimum number of connections
    maxconn=100,     # Maximum number of connections
    dsn="dbname=osm_points user=postgres"
)

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

@app.route('/api/clusters', methods=['GET'])
def get_clusters_for_locations():
    conn = None
    try:
        # Get parameters from query string
        lon1 = float(request.args.get('lon1'))
        lat1 = float(request.args.get('lat1'))
        lon2 = float(request.args.get('lon2'))
        lat2 = float(request.args.get('lat2'))
        
        # Validate coordinates
        if not (-180 <= lon1 <= 180 and -90 <= lat1 <= 90 and -180 <= lon2 <= 180 and -90 <= lat2 <= 90):
            return jsonify({'error': 'Invalid coordinates. Longitude must be between -180 and 180, latitude between -90 and 90.'}), 400
        
        # Get connection from pool
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Find cities that contain these points
        cur.execute("""
            WITH point1 AS (
                SELECT ST_SetSRID(ST_MakePoint(%s, %s), 4326) AS geom
            ),
            point2 AS (
                SELECT ST_SetSRID(ST_MakePoint(%s, %s), 4326) AS geom
            ),
            cities1 AS (
                SELECT c.id, c.name
                FROM cities c, point1 p
                WHERE ST_Contains(c.geom, p.geom)
            ),
            cities2 AS (
                SELECT c.id, c.name
                FROM cities c, point2 p
                WHERE ST_Contains(c.geom, p.geom)
            ),
            all_cities AS (
                SELECT id, name FROM cities1
                UNION
                SELECT id, name FROM cities2
            )
            SELECT id, name FROM all_cities
        """, (lon1, lat1, lon2, lat2))
        
        cities = cur.fetchall()
        
        if not cities:
            return jsonify({
                'count': 0,
                'message': 'No cities found containing the specified locations',
                'clusters': []
            })
        
        # Get city IDs
        city_ids = [city['id'] for city in cities]
        city_names = [city['name'] for city in cities]
        
        # Get clusters for these cities
        placeholders = ','.join(['%s'] * len(city_ids))
        query = f"""
            SELECT 
                pc.id,
                pc.city_id,
                c.name as city_name,
                pc.cluster_id,
                pc.point_count,
                ST_X(pc.geom) as longitude,
                ST_Y(pc.geom) as latitude
            FROM poi_clusters pc
            JOIN cities c ON pc.city_id = c.id
            WHERE pc.city_id IN ({placeholders})
            ORDER BY pc.point_count DESC
        """
        
        cur.execute(query, city_ids)
        clusters = cur.fetchall()
        
        # Group clusters by city
        clusters_by_city = {}
        for city_name in city_names:
            clusters_by_city[city_name] = []
            
        for cluster in clusters:
            city_name = cluster['city_name']
            if city_name in clusters_by_city:
                # Remove city_name from the cluster object to avoid redundancy
                del cluster['city_name']
                clusters_by_city[city_name].append(cluster)
        
        # Prepare response
        response = {
            'count': len(clusters),
            'cities': [{'name': name, 'clusters': clusters_by_city[name]} for name in city_names],
            'locations': [
                {'longitude': lon1, 'latitude': lat1},
                {'longitude': lon2, 'latitude': lat2}
            ]
        }
        
        cur.close()
        return jsonify(response)
        
    except Exception as e:
        logging.error(f"Error in get_clusters_for_locations: {str(e)}")
        return jsonify({'error': str(e)}), 400
    finally:
        if conn:
            return_db_connection(conn)  # Return connection to pool

# Meeting API endpoints
@app.route('/api/meetings', methods=['POST'])
def create_meeting():
    conn = None
    try:
        # Generate a unique token
        token = str(uuid.uuid4())
        
        # Get connection from pool
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Insert new meeting with 'created' status
        cur.execute("""
            INSERT INTO meetings (token, status)
            VALUES (%s, %s)
            RETURNING id, token, status, created_at
        """, (token, 'created'))
        
        meeting = cur.fetchone()
        conn.commit()
        cur.close()
        
        return jsonify({
            'success': True,
            'meeting': meeting
        })
    except Exception as e:
        logging.error(f"Error creating meeting: {str(e)}")
        return jsonify({'error': str(e)}), 400
    finally:
        if conn:
            return_db_connection(conn)

@app.route('/api/meetings/<token>/suggest', methods=['POST'])
def suggest_meeting(token):
    conn = None
    try:
        # Get location from request
        data = request.get_json()
        if not data or 'longitude' not in data or 'latitude' not in data:
            return jsonify({'error': 'Missing location data'}), 400
        
        longitude = float(data['longitude'])
        latitude = float(data['latitude'])
        
        # Validate coordinates
        if not (-180 <= longitude <= 180 and -90 <= latitude <= 90):
            return jsonify({'error': 'Invalid coordinates'}), 400
        
        # Get connection from pool
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Check if meeting exists
        cur.execute("SELECT * FROM meetings WHERE token = %s", (token,))
        meeting = cur.fetchone()
        
        if not meeting:
            return jsonify({'error': 'Meeting not found'}), 404
        
        # Update meeting with suggested location and status
        cur.execute("""
            UPDATE meetings 
            SET location_lon = %s, location_lat = %s, status = %s, updated_at = NOW()
            WHERE token = %s
            RETURNING id, token, status, location_lon, location_lat, created_at, updated_at
        """, (longitude, latitude, 'suggested', token))
        
        updated_meeting = cur.fetchone()
        conn.commit()
        cur.close()
        
        return jsonify({
            'success': True,
            'meeting': updated_meeting
        })
    except Exception as e:
        logging.error(f"Error suggesting meeting: {str(e)}")
        return jsonify({'error': str(e)}), 400
    finally:
        if conn:
            return_db_connection(conn)

@app.route('/api/meetings/<token>/resuggest', methods=['POST'])
def resuggest_meeting(token):
    conn = None
    try:
        # Get location from request
        data = request.get_json()
        if not data or 'longitude' not in data or 'latitude' not in data:
            return jsonify({'error': 'Missing location data'}), 400
        
        longitude = float(data['longitude'])
        latitude = float(data['latitude'])
        
        # Validate coordinates
        if not (-180 <= longitude <= 180 and -90 <= latitude <= 90):
            return jsonify({'error': 'Invalid coordinates'}), 400
        
        # Get connection from pool
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Check if meeting exists
        cur.execute("SELECT * FROM meetings WHERE token = %s", (token,))
        meeting = cur.fetchone()
        
        if not meeting:
            return jsonify({'error': 'Meeting not found'}), 404
        
        # Update meeting with new suggested location and status
        cur.execute("""
            UPDATE meetings 
            SET location_lon = %s, location_lat = %s, status = %s, updated_at = NOW()
            WHERE token = %s
            RETURNING id, token, status, location_lon, location_lat, created_at, updated_at
        """, (longitude, latitude, 'resuggested', token))
        
        updated_meeting = cur.fetchone()
        conn.commit()
        cur.close()
        
        return jsonify({
            'success': True,
            'meeting': updated_meeting
        })
    except Exception as e:
        logging.error(f"Error resuggesting meeting: {str(e)}")
        return jsonify({'error': str(e)}), 400
    finally:
        if conn:
            return_db_connection(conn)

@app.route('/api/meetings/<token>/accept', methods=['POST'])
def accept_meeting(token):
    conn = None
    try:
        # Get connection from pool
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Check if meeting exists
        cur.execute("SELECT * FROM meetings WHERE token = %s", (token,))
        meeting = cur.fetchone()
        
        if not meeting:
            return jsonify({'error': 'Meeting not found'}), 404
        
        # Check if meeting has a suggested location
        if meeting['location_lon'] is None or meeting['location_lat'] is None:
            return jsonify({'error': 'Meeting has no suggested location'}), 400
        
        # Update meeting status
        cur.execute("""
            UPDATE meetings 
            SET status = %s, updated_at = NOW()
            WHERE token = %s
            RETURNING id, token, status, location_lon, location_lat, created_at, updated_at
        """, ('accepted', token))
        
        updated_meeting = cur.fetchone()
        conn.commit()
        cur.close()
        
        return jsonify({
            'success': True,
            'meeting': updated_meeting
        })
    except Exception as e:
        logging.error(f"Error accepting meeting: {str(e)}")
        return jsonify({'error': str(e)}), 400
    finally:
        if conn:
            return_db_connection(conn)

@app.route('/api/meetings/<token>/reject', methods=['POST'])
def reject_meeting(token):
    conn = None
    try:
        # Get connection from pool
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Check if meeting exists
        cur.execute("SELECT * FROM meetings WHERE token = %s", (token,))
        meeting = cur.fetchone()
        
        if not meeting:
            return jsonify({'error': 'Meeting not found'}), 404
        
        # Update meeting status
        cur.execute("""
            UPDATE meetings 
            SET status = %s, updated_at = NOW()
            WHERE token = %s
            RETURNING id, token, status, location_lon, location_lat, created_at, updated_at
        """, ('rejected', token))
        
        updated_meeting = cur.fetchone()
        conn.commit()
        cur.close()
        
        return jsonify({
            'success': True,
            'meeting': updated_meeting
        })
    except Exception as e:
        logging.error(f"Error rejecting meeting: {str(e)}")
        return jsonify({'error': str(e)}), 400
    finally:
        if conn:
            return_db_connection(conn)

@app.route('/api/meetings/<token>/cancel', methods=['POST'])
def cancel_meeting(token):
    conn = None
    try:
        # Get connection from pool
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Check if meeting exists
        cur.execute("SELECT * FROM meetings WHERE token = %s", (token,))
        meeting = cur.fetchone()
        
        if not meeting:
            return jsonify({'error': 'Meeting not found'}), 404
        
        # Update meeting status
        cur.execute("""
            UPDATE meetings 
            SET status = %s, updated_at = NOW()
            WHERE token = %s
            RETURNING id, token, status, location_lon, location_lat, created_at, updated_at
        """, ('cancelled', token))
        
        updated_meeting = cur.fetchone()
        conn.commit()
        cur.close()
        
        return jsonify({
            'success': True,
            'meeting': updated_meeting
        })
    except Exception as e:
        logging.error(f"Error cancelling meeting: {str(e)}")
        return jsonify({'error': str(e)}), 400
    finally:
        if conn:
            return_db_connection(conn)

@app.route('/api/meetings/<token>', methods=['GET'])
def get_meeting(token):
    conn = None
    try:
        # Get connection from pool
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Get meeting by token
        cur.execute("SELECT * FROM meetings WHERE token = %s", (token,))
        meeting = cur.fetchone()
        
        if not meeting:
            return jsonify({'error': 'Meeting not found'}), 404
        
        cur.close()
        
        return jsonify({
            'success': True,
            'meeting': meeting
        })
    except Exception as e:
        logging.error(f"Error getting meeting: {str(e)}")
        return jsonify({'error': str(e)}), 400
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