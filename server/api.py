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
        
        # Query points within bbox
        cur.execute("""
            SELECT id, 
                   ST_X(geom) as longitude,
                   ST_Y(geom) as latitude
            FROM osm_points
            WHERE ST_X(geom) BETWEEN %s AND %s
            AND ST_Y(geom) BETWEEN %s AND %s
        """, (min_lon, max_lon, min_lat, max_lat))
        
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

@app.route('/api/clusters', methods=['GET'])
def get_clusters():
    try:
        # Get parameters from query string
        min_lon = float(request.args.get('minLon'))
        min_lat = float(request.args.get('minLat'))
        max_lon = float(request.args.get('maxLon'))
        max_lat = float(request.args.get('maxLat'))
        num_clusters = int(request.args.get('clusters', 5))  # default to 5 clusters
        
        # Connect to database
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Query clusters using PostgreSQL's k-means
        cur.execute("""
            WITH points AS (
                SELECT id, geom
                FROM osm_points
                WHERE ST_X(geom) BETWEEN %s AND %s
                AND ST_Y(geom) BETWEEN %s AND %s
            ),
            clusters AS (
                SELECT 
                    cluster_id,
                    ST_Centroid(ST_Collect(geom)) as center,
                    COUNT(*) as point_count
                FROM (
                    SELECT 
                        id,
                        geom,
                        ST_ClusterKMeans(geom, %s) 
                        OVER () as cluster_id
                    FROM points
                ) clusters
                GROUP BY cluster_id
            )
            SELECT 
                cluster_id,
                ST_X(center) as longitude,
                ST_Y(center) as latitude,
                point_count
            FROM clusters
            ORDER BY point_count DESC
        """, (min_lon, max_lon, min_lat, max_lat, num_clusters))
        
        clusters = cur.fetchall()
        
        # Close database connection
        cur.close()
        conn.close()
        
        return jsonify({
            'count': len(clusters),
            'clusters': clusters
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)