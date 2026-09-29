import os
import geopandas as gpd
from shapely.geometry import Point

# Paths to the static assets we generated in Step 1
DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")
ROADS_PATH = os.path.join(DATA_DIR, "kerala_roads_major.geojson")
DISTRICTS_PATH = os.path.join(DATA_DIR, "kerala_districts.geojson")

# Load static maps into memory once on startup to ensure rapid API responses
try:
    major_roads_gdf = gpd.read_file(ROADS_PATH)
    districts_gdf = gpd.read_file(DISTRICTS_PATH)
except Exception as e:
    print(f"Warning: Could not load static maps. Ensure Step 1 is complete. {e}")
    major_roads_gdf = None
    districts_gdf = None

def get_flooded_roads(district_name: str, estimated_depth_cm: float) -> list:
    """
    Checks if the estimated depth exceeds the 20cm vehicle stall threshold.
    If so, flags major roads intersecting that district.
    """
    if estimated_depth_cm < 20.0 or major_roads_gdf is None or districts_gdf is None:
        return []

    # Find the specific district polygon
    target_district = districts_gdf[districts_gdf['district'] == district_name]
    if target_district.empty:
        return []
    
    district_geom = target_district.geometry.iloc[0]

    # Intersect the major roads with the district boundary
    intersecting_roads = major_roads_gdf[major_roads_gdf.intersects(district_geom)]
    
    # Extract unique road names, ignoring unnamed segments
    affected_roads = intersecting_roads['name'].dropna().unique().tolist()
    
    return [road for road in affected_roads if road.strip() != ""]