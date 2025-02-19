from flask import Flask, request, jsonify # type: ignore
import psycopg2 # type: ignore
from psycopg2.extras import RealDictCursor # type: ignore

app = Flask(__name__)

def get_db_connection():
    return psycopg2.connect("dbname=osm_points user=postgres")

@app.route('/api/points', methods=['GET'])
def get_points_in_bbox():
    try:
        # Get parameters from query string
        min_lon = float(request.args.get('minLon'))
        min_lat = float(request.args.get('minLat'))
        max_lon = float(request.args.get('maxLon'))
        max_lat = float(request.args.get('maxLat'))
        
        # Connect to database
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
        
        # Close database connection
        cur.close()
        conn.close()
        
        return jsonify({
            'count': len(points),
            'points': points
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 400
    
def ST_ClusterKMeans(min_lon, min_lat, max_lon, max_lat, num_clusters=5):
    try:
        # Connect to database
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Query clusters using PostgreSQL's k-means
        cur.execute("""
            WITH points AS (
                SELECT id, geom
                FROM osm_points
                WHERE geom && ST_MakeEnvelope(%s, %s, %s, %s, 4326)
            ),
            point_count AS (
                SELECT COUNT(*) as total FROM points
            ),
            result AS (
                SELECT 
                    CASE 
                        WHEN (SELECT total FROM point_count) <= %s THEN id::text
                        ELSE ST_ClusterKMeans(geom, 
                            LEAST((SELECT total FROM point_count), %s)::integer
                        ) OVER ()::text
                    END as cluster_id,
                    geom
                FROM points
            ),
            final AS (
                SELECT 
                    cluster_id,
                    ST_Centroid(ST_Collect(geom)) as center,
                    COUNT(*) as point_count
                FROM result
                GROUP BY cluster_id
            )
            SELECT 
                cluster_id,
                ST_X(center) as longitude,
                ST_Y(center) as latitude,
                point_count,
                (SELECT total <= %s FROM point_count) as is_individual_points
            FROM final
            ORDER BY point_count DESC
        """, (min_lon, min_lat, max_lon, max_lat, num_clusters, num_clusters, num_clusters))
        
        results = cur.fetchall()

        # Close database connection
        cur.close()
        conn.close()
        
        return jsonify({
            'count': len(results),
            'clusters': results,
            'is_clustered': not (results[0]['is_individual_points'] if results else False)
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 400
    
def ST_ClusterDBSCAN(min_lon, min_lat, max_lon, max_lat, eps=0.01, min_points=2):
    try:
        # Connect to database
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Query clusters using PostgreSQL's DBSCAN
        cur.execute("""
            WITH points AS (
                SELECT id, geom
                FROM osm_points
                WHERE geom && ST_MakeEnvelope(%s, %s, %s, %s, 4326)
            ),
            point_count AS (
                SELECT COUNT(*) as total FROM points
            ),
            result AS (
                SELECT 
                    CASE
                        WHEN (SELECT total FROM point_count) <= %s THEN id::text
                        ELSE ST_ClusterDBSCAN(geom, eps := %s, minpoints := %s) OVER ()::text
                    END as cluster_id,
                    geom
                FROM points
            ),
            final AS (
                SELECT 
                    cluster_id,
                    ST_Centroid(ST_Collect(geom)) as center,
                    COUNT(*) as point_count
                FROM result
                GROUP BY cluster_id
            )
            SELECT 
                cluster_id,
                ST_X(center) as longitude,
                ST_Y(center) as latitude,
                point_count,
                (SELECT total <= %s FROM point_count) as is_individual_points
            FROM final
            ORDER BY point_count DESC
        """, (min_lon, min_lat, max_lon, max_lat, min_points, eps, min_points, min_points))
        
        results = cur.fetchall()
        
        # Close database connection
        cur.close()
        conn.close()
        
        return jsonify({
            'count': len(results),
            'clusters': results,
            'is_clustered': not (results[0]['is_individual_points'] if results else False)
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 400
    
@app.route('/api/two-point-clusters', methods=['GET'])
def get_clusters_between_points():
    try:
        # Get parameters for two points
        lon1 = float(request.args.get('lon1'))
        lat1 = float(request.args.get('lat1'))
        lon2 = float(request.args.get('lon2'))
        lat2 = float(request.args.get('lat2'))
        
        method = request.args.get('method', 'kmeans')
        num_clusters = int(request.args.get('clusters', 5))
        max_distance = float(request.args.get('maxDistance', 0.00025))
        
        # Create bounding box from the two points
        min_lon = min(lon1, lon2)
        max_lon = max(lon1, lon2)
        min_lat = min(lat1, lat2)
        max_lat = max(lat1, lat2)
        
        # Add some padding to the bounding box (e.g., 10% on each side)
        lon_padding = (max_lon - min_lon) * 0.1
        lat_padding = (max_lat - min_lat) * 0.1
        
        min_lon -= lon_padding
        max_lon += lon_padding
        min_lat -= lat_padding
        max_lat += lat_padding

        if method == 'kmeans':
            results = ST_ClusterKMeans(min_lon, min_lat, max_lon, max_lat, num_clusters)
        elif method == 'dbscan':
            results = ST_ClusterDBSCAN(min_lon, min_lat, max_lon, max_lat, max_distance, 2)

        return results
    except Exception as e:
        return jsonify({'error': str(e)}), 400

if __name__ == '__main__':
    ssl_cert = '/etc/letsencrypt/live/snf-78417.ok-kno.grnetcloud.net/fullchain.pem'
    ssl_key = '/etc/letsencrypt/live/snf-78417.ok-kno.grnetcloud.net/privkey.pem'
    
    app.run(
        host='0.0.0.0',
        port=443,  # Changed to standard HTTPS port
        debug=True,
        ssl_context=(ssl_cert, ssl_key)
    )