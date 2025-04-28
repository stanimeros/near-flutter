import geopandas as gpd # type: ignore
import psycopg2 # type: ignore
from shapely.geometry import Polygon, MultiPolygon # type: ignore
from shapely import wkt # type: ignore
from shapely.ops import transform # type: ignore
from psycopg2 import sql # type: ignore
import pyproj # type: ignore
import time

def connect_db():
    """Connect to the PostgreSQL database."""
    print("Connecting to database...")
    conn = psycopg2.connect("dbname=osm_points user=postgres")
    print("Connected to database")
    return conn

def to_wgs84(geometry):
    """Convert geometry from EPSG:2100 to EPSG:4326"""
    project = pyproj.Transformer.from_crs('EPSG:2100', 'EPSG:4326', always_xy=True)
    return transform(project.transform, geometry)

def drop_and_create_tables(conn):
    """Drop and create necessary tables if they don't exist."""
    try:
        cur = conn.cursor()

        # Drop poi_clusters first since it depends on cities
        print("Dropping poi_clusters table...")
        cur.execute("DROP TABLE IF EXISTS poi_clusters CASCADE")
        
        # Drop cities table
        print("Dropping cities table...")
        cur.execute("DROP TABLE IF EXISTS cities CASCADE")
        
        print("Creating cities table...")
        # Create cities table
        cur.execute("""
        CREATE TABLE cities (
            id SERIAL PRIMARY KEY,
            name VARCHAR(255),
            geom GEOMETRY(POLYGON, 4326)
        );
        """)
        
        # Create spatial index
        cur.execute("""
        CREATE INDEX cities_geom_idx ON cities USING GIST (geom);
        """)
        
        conn.commit()
        cur.close()
        print("Tables created")
    except Exception as e:
        print(f"Error creating tables: {e}")
        conn.rollback()

def insert_city(conn, city_name, city_geometry):
    """Insert a city into the cities table."""
    try:
        cur = conn.cursor()
        
        # Convert the geometry to WGS84 (EPSG:4326)
        try:
            city_geometry_wgs84 = to_wgs84(city_geometry)
            city_wkt = wkt.dumps(city_geometry_wgs84)
        except Exception as e:
            print(f"Error transforming {city_name}: {e}")
            return
        
        insert_query = sql.SQL("""
        INSERT INTO cities (name, geom)
        VALUES (%s, ST_SetSRID(ST_GeomFromText(%s), 4326))
        """)
        
        cur.execute(insert_query, (city_name, city_wkt))
        conn.commit()
        cur.close()
    except Exception as e:
        print(f"Error inserting city {city_name}: {e}")
        conn.rollback()

def add_cities_to_db():
    """Add cities from the GeoJSON file to the database."""
    geojson_file = 'otas.geojson'
    start_time = time.time()
    try:
        # Load the GeoJSON file
        print(f"Reading GeoJSON file: {geojson_file}")
        cities_gdf = gpd.read_file(geojson_file)
        print(f"Found {len(cities_gdf)} cities in GeoJSON")
        
        # Establish DB connection
        conn = connect_db()
        
        # Create tables if they don't exist
        drop_and_create_tables(conn)
        
        # Insert each city into the database
        print("Starting city import...")
        processed_count = 0
        
        for _, city_row in cities_gdf.iterrows():
            city_name = city_row['OTA_LEKTIK']
            city_geometry = city_row['geometry']
            
            if isinstance(city_geometry, Polygon):
                insert_city(conn, city_name, city_geometry)
                processed_count += 1
            elif isinstance(city_geometry, MultiPolygon):
                for polygon in city_geometry.geoms:
                    insert_city(conn, city_name, polygon)
                    processed_count += 1
            else:
                print(f"Skipping city {city_name} because it's not a Polygon or MultiPolygon: {type(city_geometry)}")
            
            # Show progress every 10 cities
            if processed_count % 10 == 0:
                print(f"Progress: {processed_count}/{len(cities_gdf)} cities processed")
        
        # Close DB connection
        conn.close()
        
        elapsed_time = time.time() - start_time
        print(f"Import completed in {elapsed_time:.2f} seconds")
        print(f"Summary: {processed_count} cities imported")
        
    except Exception as e:
        print(f"Error in add_cities_to_db: {e}")

if __name__ == "__main__":
    add_cities_to_db()
