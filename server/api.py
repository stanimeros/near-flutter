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
    
def perform_clustering(min_lon, min_lat, max_lon, max_lat, num_clusters=5):
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
                        ELSE ST_ClusterKMeans(geom, %s) OVER ()::text
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
        
        return jsonify({
            'count': len(results),
            'clusters': results,
            'is_clustered': not (results[0]['is_individual_points'] if results else False)
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 400

@app.route('/api/clusters', methods=['GET'])
def get_clusters():
    try:
        # Connect to database
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)

        # Get parameters from query string
        min_lon = float(request.args.get('minLon'))
        min_lat = float(request.args.get('minLat'))
        max_lon = float(request.args.get('maxLon'))
        max_lat = float(request.args.get('maxLat'))
        num_clusters = int(request.args.get('clusters', 5))  # default to 5 clusters
        
        results = perform_clustering(min_lon, min_lat, max_lon, max_lat, num_clusters)

        # Close database connection
        cur.close()
        conn.close()

        return results
    except Exception as e:
        return jsonify({'error': str(e)}), 400
    
@app.route('/api/two-point-clusters', methods=['GET'])
def get_clusters_between_points():
    try:
        # Connect to database
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)

        # Get parameters for two points
        lon1 = float(request.args.get('lon1'))
        lat1 = float(request.args.get('lat1'))
        lon2 = float(request.args.get('lon2'))
        lat2 = float(request.args.get('lat2'))
        num_clusters = int(request.args.get('clusters', 5))
    
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
        
        results = perform_clustering(min_lon, min_lat, max_lon, max_lat, num_clusters)

        # Close database connection
        cur.close()
        conn.close()

        return results
    except Exception as e:
        return jsonify({'error': str(e)}), 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)