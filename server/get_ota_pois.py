import requests
import geopandas as gpd # type: ignore
from shapely.geometry import Point, Polygon # type: ignore
from shapely.ops import transform # type: ignore
import pyproj # type: ignore

# Load the GeoJSON containing the city polygons
cities_gdf = gpd.read_file('otas.geojson')

# Define the Overpass API endpoint
overpass_url = "http://overpass-api.de/api/interpreter"

# Function to convert coordinates from EPSG:2100 to EPSG:4326 (WGS84)
def to_wgs84(lon, lat):
    # Define the transformation from EPSG:2100 to EPSG:4326
    in_proj = pyproj.CRS('EPSG:2100')
    out_proj = pyproj.CRS('EPSG:4326')
    project = pyproj.Transformer.from_crs(in_proj, out_proj, always_xy=True)
    return project.transform(lon, lat)

# Initialize an empty list to store POIs for all cities
all_pois = []

# Loop through each city's polygon
for index, city_row in cities_gdf.iterrows():
    # Use 'OTA_LEKTIK' field for city name
    city_name = city_row['OTA_LEKTIK']
    city_polygon = city_row['geometry']

    if isinstance(city_polygon, Polygon):  # Ensure it's a polygon
        # Convert the polygon's bounding box to EPSG:4326 (WGS84)
        minx, miny, maxx, maxy = city_polygon.bounds
        
        # Transform the bounding box from EPSG:2100 to EPSG:4326
        minx, miny = to_wgs84(minx, miny)
        maxx, maxy = to_wgs84(maxx, maxy)
        
        # Print the transformed bounding box for debugging
        print(f"Bounding box for {city_name}:")
        print(f"Minx: {minx}, Miny: {miny}, Maxx: {maxx}, Maxy: {maxy}")

        # Overpass query to get POIs within the city's bounding box
        overpass_query = f"""
        [out:json];
        (
          node({miny},{minx},{maxy},{maxx});
          way({miny},{minx},{maxy},{maxx});
          relation({miny},{minx},{maxy},{maxx});
        );
        out body;
        """

        # Request POIs from Overpass API
        response = requests.get(overpass_url, params={'data': overpass_query})

        # Check if the response is valid (status code 200)
        if response.status_code == 200:
            try:
                data = response.json()  # Attempt to parse the response as JSON
                # Extract POIs from the Overpass response
                for element in data.get('elements', []):
                    if 'tags' in element:
                        # Create a Point geometry for each POI (only if 'lon' and 'lat' are available)
                        if 'lon' in element and 'lat' in element:
                            poi_point = Point(element['lon'], element['lat'])

                            # Check if the POI is within the city polygon
                            if city_polygon.contains(poi_point):
                                poi_data = element['tags']
                                poi_data['geometry'] = poi_point
                                poi_data['OTA_LEKTIK'] = city_name  # Assign the city name to the POI
                                all_pois.append(poi_data)

            except ValueError:
                print(f"Error: Failed to decode JSON for {city_name}.")
        else:
            print(f"Error: Overpass API responded with status code {response.status_code} for {city_name}.")

# Convert the list of POIs to a GeoDataFrame
if all_pois:
    gdf_pois = gpd.GeoDataFrame(all_pois, geometry='geometry', crs="EPSG:4326")

    # Save the POIs to a GeoPackage file (PostGIS-compatible)
    output_file = "pois_for_cities.gpkg"
    gdf_pois.to_file(output_file, driver="GPKG")

    print(f"Extracted {len(gdf_pois)} POIs and saved to {output_file}")
else:
    print("No POIs found.")

