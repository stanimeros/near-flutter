import geopandas as gpd # type: ignore
import psycopg2 # type: ignore
from shapely.geometry import Polygon, MultiPolygon # type: ignore
from shapely.ops import unary_union, transform # type: ignore
from shapely import wkt # type: ignore
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
    project = pyproj.Transformer.from_crs('EPSG:2100', 'EPSG:4326', always_xy=True)
    return transform(project.transform, geometry)

def drop_and_create_tables(conn):
    try:
        cur = conn.cursor()
        print("Dropping poi_clusters table...")
        cur.execute("DROP TABLE IF EXISTS poi_clusters CASCADE")
        print("Dropping cities table...")
        cur.execute("DROP TABLE IF EXISTS cities CASCADE")
        print("Creating cities table...")
        cur.execute("""
        CREATE TABLE cities (
            id SERIAL PRIMARY KEY,
            name VARCHAR(255),
            geom GEOMETRY(MultiPolygon, 4326)
        );
        """)
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
    try:
        cur = conn.cursor()
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
    geojson_file = 'otas.geojson'
    start_time = time.time()
    try:
        print(f"Reading GeoJSON file: {geojson_file}")
        cities_gdf = gpd.read_file(geojson_file)
        print(f"Found {len(cities_gdf)} cities in GeoJSON")
        conn = connect_db()
        drop_and_create_tables(conn)
        print("Starting city import...")

        # Group all polygons by city name
        cities = {}
        for _, city_row in cities_gdf.iterrows():
            city_name = city_row['OTA_LEKTIK']
            city_geometry = city_row['geometry']
            if city_name not in cities:
                cities[city_name] = []
            if isinstance(city_geometry, Polygon):
                cities[city_name].append(city_geometry)
            elif isinstance(city_geometry, MultiPolygon):
                cities[city_name].extend(list(city_geometry.geoms))
            else:
                print(f"Skipping city {city_name} because it's not a Polygon or MultiPolygon but {type(city_geometry)}")

        processed_count = 0
        for city_name, polygons in cities.items():
            if not polygons:
                continue
            unioned = unary_union(polygons)
            insert_city(conn, city_name, unioned)
            processed_count += 1
            if processed_count % 10 == 0:
                print(f"Progress: {processed_count}/{len(cities)} city names processed")

        conn.close()
        elapsed_time = time.time() - start_time
        print(f"Import completed in {elapsed_time:.2f} seconds")
        print(f"Summary: {processed_count} cities imported")
    except Exception as e:
        print(f"Error in add_cities_to_db: {e}")

if __name__ == "__main__":
    add_cities_to_db()
