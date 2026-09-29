import geopandas as gpd

def build_roads_offline():
    print("Reading local road data from your hard drive...")
    
    # Point this to the extracted shapefile
    shapefile_path = "kerala_roads/gis_osm_roads_free_1.shp"
    gdf = gpd.read_file(shapefile_path)
    
    print("Filtering for major highways...")
    # Keep only the major connecting roads to keep the backend fast
    major_classes = ['motorway', 'trunk', 'primary', 'secondary']
    major_roads = gdf[gdf['fclass'].isin(major_classes)]
    
    print("Saving to GeoJSON...")
    output_path = "app/data/kerala_roads_major.geojson"
    
    # Export exactly what your backend needs
    major_roads.to_file(output_path, driver="GeoJSON")
    print(f"Success! Offline roads saved to {output_path}")

if __name__ == "__main__":
    build_roads_offline()