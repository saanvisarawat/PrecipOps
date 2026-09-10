from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Dict, Any

router = APIRouter()

# --- Data Schemas ---
class InundationPolygon(BaseModel):
    zone_id: str
    severity: str
    avg_water_depth_meters: float
    affected_landmarks: List[str]
    geojson_geometry: Dict[str, Any]

class PS71Response(BaseModel):
    timestamp: str
    district: str
    lead_time_warning: str
    alert_level: str
    meteorological_inputs: Dict[str, Any]
    inundation_zones: List[InundationPolygon]
    advisory_bulletin: str

# --- The Endpoint ---
@router.get("/heavy-rainfall/predict", response_model=PS71Response)
async def predict_inundation(district: str = "Ernakulam"):
    # 1. The 4 Mandatory Feeds
    telemetry = {
        "satellite": {
            "source": "INSAT-3DR",
            "cloud_top_temp_kelvin": 202.4,
            "rainfall_hydro_estimator_mm_hr": 68.5
        },
        "radar": {
            "station": f"DWR {district}",
            "reflectivity_dbz": 53.2,
            "radial_velocity_mps": -14.2
        },
        "observational_weather": {
            "sensor_type": "IMD AWS",
            "current_rainfall_mm_hr": 72.0,
            "cumulative_24h_rainfall_mm": 184.0
        },
        "numerical_weather_prediction": {
            "model_name": "NCMRWF Unified Model",
            "predicted_precipitation_mm": 95.0
        }
    }

    # 2. GeoJSON Polygons for Inundation
    # A simple square polygon roughly around Kochi for the frontend
    polygon = {
        "type": "Polygon",
        "coordinates": [[
            [76.28, 9.97], [76.31, 9.97], 
            [76.31, 10.00], [76.28, 10.00], 
            [76.28, 9.97]
        ]]
    }

    zones = [
        InundationPolygon(
            zone_id=f"INUND-{district.upper()}-01",
            severity="CRITICAL",
            avg_water_depth_meters=1.45,
            affected_landmarks=["MG Road", "Low-lying Market Ward"],
            geojson_geometry=polygon
        )
    ]

    bulletin = f"IMD BULLETIN: Severe convective storm detected via DWR (53.2 dBZ). Expected inundation of 1.45m in {district}."

    return PS71Response(
        timestamp="2026-09-11T00:00:00Z",
        district=district,
        lead_time_warning="0 - 3 Hours Immediate Inundation",
        alert_level="RED",
        meteorological_inputs=telemetry,
        inundation_zones=zones,
        advisory_bulletin=bulletin
    )