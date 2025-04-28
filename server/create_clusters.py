import psycopg2 # type: ignore
from psycopg2.extras import DictCursor # type: ignore
import time

# DBSCAN parameters - final working values
EPS = 0.0006
MIN_POINTS = 50

def connect_db():
    """Connect to the PostgreSQL database."""
    print("Connecting to database...")
    conn = psycopg2.connect("dbname=osm_points user=postgres")
    print("Connected to database")
    return conn

def drop_and_create_table(conn):
    """Drop and recreate the poi_clusters table."""
    try:
        cur = conn.cursor()
        
        # Drop the table if it exists
        print("Dropping poi_clusters table...")
        cur.execute("DROP TABLE IF EXISTS poi_clusters CASCADE")
        
        # Create poi_clusters table
        print("Creating poi_clusters table...")
        cur.execute("""
        CREATE TABLE poi_clusters (
            id SERIAL PRIMARY KEY,
            city_id INTEGER REFERENCES cities(id),
            cluster_id INTEGER,
            point_count INTEGER,
            geom GEOMETRY(POINT, 4326),
            created_at TIMESTAMP DEFAULT NOW()
        );
        """)
        
        # Create spatial index
        cur.execute("""
        CREATE INDEX poi_clusters_geom_idx ON poi_clusters USING GIST (geom);
        """)
        
        conn.commit()
        cur.close()
        print("Tables recreated successfully")
    except Exception as e:
        print(f"Error creating tables: {e}")
        conn.rollback()

def check_database(conn):
    """Check if there are any points in the database."""
    print("Checking database state...")
    cur = conn.cursor()
    
    # Check total points
    cur.execute("SELECT COUNT(*) FROM osm_points")
    total_points = cur.fetchone()[0]
    print(f"Total points: {total_points}")
    
    # Check total cities
    cur.execute("SELECT COUNT(*) FROM cities")
    total_cities = cur.fetchone()[0]
    print(f"Total cities: {total_cities}")
    
    cur.close()

def process_city(conn, city_id, city_name, city_geom_wkt):
    """Process clustering for a single city."""
    try:
        cur = conn.cursor()
        
        # First, check if there are any points in this city
        check_points_query = """
        SELECT COUNT(*)
        FROM osm_points p
        WHERE ST_Contains(ST_GeomFromText(%s, 4326), p.geom)
        """
        cur.execute(check_points_query, (city_geom_wkt,))
        point_count = cur.fetchone()[0]
        
        if point_count == 0:
            print(f"No points found in {city_name}")
            return
        
        print(f"Found {point_count} points in {city_name}")
        
        # Perform DBSCAN clustering
        print(f"Clustering {city_name}...")
        
        clustering_query = """
        contained_points AS (
            SELECT p.id, p.geom
            FROM osm_points p
            WHERE ST_Contains(ST_GeomFromText(%s, 4326), p.geom)
        ),
        clustered AS (
            SELECT 
                ST_ClusterDBSCAN(geom, eps := %s, minpoints := %s) OVER () AS cluster_id,
                geom
            FROM contained_points
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
        INSERT INTO poi_clusters (city_id, cluster_id, point_count, geom)
        SELECT %s, cluster_id, point_count, center
        FROM final
        RETURNING cluster_id, point_count;
        """
        
        cur.execute(clustering_query, (city_geom_wkt, EPS, MIN_POINTS, city_id))
        clusters = cur.fetchall()
        
        conn.commit()
        
        if clusters:
            total_clusters = len(clusters)
            total_points = sum(cluster[1] for cluster in clusters)
            print(f"Created {total_clusters} clusters with {total_points} points for {city_name}")
        else:
            print(f"No clusters formed for {city_name}")
        
        cur.close()
        
    except Exception as e:
        print(f"Error processing {city_name}: {e}")
        conn.rollback()

def main():
    start_time = time.time()
    print(f"Starting clustering process")
    print(f"Parameters: EPS={EPS}, MIN_POINTS={MIN_POINTS}")
    
    try:
        conn = connect_db()
        
        # Always recreate the table
        drop_and_create_table(conn)
        
        # Check database state
        check_database(conn)
        
        # Get all unique city names
        cur = conn.cursor(cursor_factory=DictCursor)
        cur.execute("""
            SELECT name, id, ST_AsText(geom) as geom_wkt
            FROM cities
            WHERE geom IS NOT NULL
            ORDER BY name
        """)
        cities = cur.fetchall()
        
        if not cities:
            print("No cities found in database!")
            return
        
        print(f"Found {len(cities)} cities to process")
        
        # Process each city
        processed_count = 0
        for city in cities:
            city_name, city_id, city_geom_wkt = city['name'], city['id'], city['geom_wkt']

            # if city_name != "ΘΕΣΣΑΛΟΝΙΚΗΣ":
            #     continue

            print(f"\nProcessing city {processed_count+1}/{len(cities)}: {city_name}")
            process_city(conn, city_id, city_name, city_geom_wkt)
            processed_count += 1
            
            # Show progress every 10 cities
            if processed_count % 10 == 0:
                print(f"Progress: {processed_count}/{len(cities)} cities processed")
        
        # Get final statistics
        cur.execute("SELECT COUNT(*) FROM poi_clusters")
        total_clusters = cur.fetchone()[0]
        
        cur.execute("SELECT SUM(point_count) FROM poi_clusters")
        total_clustered_points = cur.fetchone()[0] or 0
        
        elapsed_time = time.time() - start_time
        print("\n=== Summary ===")
        print(f"Time: {elapsed_time:.2f} seconds")
        print(f"Cities processed: {processed_count}")
        print(f"Total clusters: {total_clusters}")
        print(f"Total points in clusters: {total_clustered_points}")
        
    except Exception as e:
        print(f"Error in main process: {e}")
    
    finally:
        if 'conn' in locals():
            conn.close()
            print("Database connection closed")

if __name__ == "__main__":
    main()
