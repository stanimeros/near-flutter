import osmium # type: ignore
import psycopg2 # type: ignore
from shapely.geometry import Point # type: ignore

class NodeHandler(osmium.SimpleHandler):
    def __init__(self):
        super(NodeHandler, self).__init__()
        self.conn = psycopg2.connect("dbname=osm_points user=postgres")
        self.cur = self.conn.cursor()
    
    def node(self, n):
        try:
            self.cur.execute("""
                INSERT INTO osm_points (id, geom)
                VALUES (%s, ST_SetSRID(ST_MakePoint(%s, %s), 4326))
                ON CONFLICT (id) DO NOTHING
            """, (n.id, n.location.lon, n.location.lat))
            
            if n.id % 10000 == 0:
                self.conn.commit()
                print(f"Processed {n.id} nodes")
        
        except Exception as e:
            print(f"Error with node {n.id}: {e}")
    
    def close(self):
        self.conn.commit()
        self.cur.close()
        self.conn.close()

handler = NodeHandler()
handler.apply_file("greece-latest.osm.pbf")
handler.close()