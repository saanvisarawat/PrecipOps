import datetime
from typing import List, Dict, Any, Optional
from fastapi import APIRouter, Query
from pydantic import BaseModel, Field

router = APIRouter(prefix="/inundation", tags=["PS 26071 Inundation & Early Warning"])

# --- Pydantic Schemas for Multi-Time Simulation ---
class InundationPolygon(BaseModel):
    zone_id: str
    severity: str
    avg_water_depth_meters: float
    affected_landmarks: List[str]
    geojson_geometry: Dict[str, Any]

class InundationFrame(BaseModel):
    time_step: str  # "T+0h (Nowcast)", "T+1h", "T+2h (Peak)", "T+3h (Receding)"
    water_depth_meters: float
    radar_dbz: float
    satellite_rain_rate_mm_hr: float
    severity: str
    affected_landmarks: List[str]
    geojson_geometry: Dict[str, Any]

class PS71SimulationResponse(BaseModel):
    timestamp: str
    district: str
    lead_time_warning: str
    alert_level: str
    meteorological_inputs: Dict[str, Any]
    inundation_zones: List[InundationPolygon]   # Peak inundation (backward compatible)
    simulation_frames: List[InundationFrame]   # Time-series frames for slider/play animation
    advisory_bulletin: str


# --- Pan-India City Registry ---
PAN_INDIA_REGISTRY = {
    "Mumbai": {
        "center": [72.842, 19.018],
        "radar": "Doppler Weather Radar (DWR) Mumbai (Colaba / Veravali)",
        "aws_id": "IMD-AWS-MUM-01",
        "landmarks": [
            "Hindmata Junction Basin",
            "Milan Subway Corridor",
            "Gandhi Market (Kings Circle)",
            "Sion Station Low-lying Road"
        ]
    },
    "Delhi": {
        "center": [77.240, 28.632],
        "radar": "Doppler Weather Radar (DWR) Delhi (Palam / Lodhi Road)",
        "aws_id": "IMD-AWS-DEL-01",
        "landmarks": [
            "ITO Ring Road Underpass",
            "Yamuna Bazar Ghat Area",
            "Kashmere Gate ISBT Basin",
            "Pragati Maidan Corridor"
        ]
    },
    "Chennai": {
        "center": [80.218, 12.985],
        "radar": "Doppler Weather Radar (DWR) Chennai (Port Trust)",
        "aws_id": "IMD-AWS-CHN-01",
        "landmarks": [
            "Velachery Lake Catchment",
            "Madipakkam Ward 188",
            "T. Nagar Usman Road Underpass",
            "Adyar River Floodplain"
        ]
    },
    "Kolkata": {
        "center": [88.363, 22.540],
        "radar": "Doppler Weather Radar (DWR) Kolkata (New Town)",
        "aws_id": "IMD-AWS-KOL-01",
        "landmarks": [
            "Thanthania Kalibari Basin",
            "Park Circus 7-Point Lowlands",
            "Behala Ward 122 Drainage Corridor",
            "EM Bypass Sub-Canal Road"
        ]
    },
    "Guwahati": {
        "center": [91.765, 26.155],
        "radar": "Doppler Weather Radar (DWR) Guwahati (LGBI Airport)",
        "aws_id": "IMD-AWS-GAU-01",
        "landmarks": [
            "Rukminigaon GS Road Axis",
            "Anil Nagar Canal Overflow Basin",
            "Nabin Nagar Low-elevation Sector",
            "Zoo Road Downstream Ward"
        ]
    },
    "Ernakulam": {
        "center": [76.285, 9.975],
        "radar": "Doppler Weather Radar (DWR) Kochi (Naval Base)",
        "aws_id": "IMD-AWS-ERN-01",
        "landmarks": [
            "MG Road Metro Corridor",
            "Railway Colony Basin",
            "Kaloor Stadium Low-lying Ward",
            "Central Broadway Market Ward"
        ]
    }
}


def build_geojson_polygon(lon: float, lat: float, delta: float) -> Dict[str, Any]:
    """Generates a valid closed GeoJSON Polygon ring centered at (lon, lat)."""
    return {
        "type": "Polygon",
        "coordinates": [[
            [round(lon - delta, 5), round(lat - delta, 5)],
            [round(lon + delta, 5), round(lat - delta, 5)],
            [round(lon + delta, 5), round(lat + delta, 5)],
            [round(lon - delta, 5), round(lat + delta, 5)],
            [round(lon - delta, 5), round(lat - delta, 5)]
        ]]
    }


# Shared business logic
async def _execute_inundation_pipeline(district: str, scenario: str) -> PS71SimulationResponse:
    now = datetime.datetime.utcnow().isoformat() + "Z"

    # 1. Match city profile or fallback to Mumbai
    city_key = next((k for k in PAN_INDIA_REGISTRY if k.lower() == district.strip().lower()), "Mumbai")
    city = PAN_INDIA_REGISTRY[city_key]
    lon, lat = city["center"]

    # 2. Configure Scenarios & Time-Series Evolution
    if scenario == "EXTREME_EVENT":
        alert = "RED"
        lead_time = "0 - 3 Hours Nowcast (Immediate Inundation Expected)"
        
        simulation_steps = [
            {
                "t": "T+0h (Nowcast)",
                "depth": 0.25,
                "dbz": 39.5,
                "rain": 28.0,
                "delta": 0.007,
                "sev": "MODERATE",
                "landmarks": city["landmarks"][:1]
            },
            {
                "t": "T+1h",
                "depth": 0.75,
                "dbz": 48.0,
                "rain": 52.0,
                "delta": 0.012,
                "sev": "HIGH",
                "landmarks": city["landmarks"][:2]
            },
            {
                "t": "T+2h (Peak Inundation)",
                "depth": 1.45,
                "dbz": 54.2,
                "rain": 72.0,
                "delta": 0.018,
                "sev": "CRITICAL",
                "landmarks": city["landmarks"]
            },
            {
                "t": "T+3h (Receding)",
                "depth": 0.85,
                "dbz": 32.0,
                "rain": 14.0,
                "delta": 0.013,
                "sev": "HIGH",
                "landmarks": city["landmarks"][:2]
            }
        ]

        bulletin = (
            f"IMD HIGH-SEVERITY BULLETIN ({city_key.upper()} METROPOLITAN AREA): "
            f"Fused Doppler Radar ({simulation_steps[2]['dbz']} dBZ) and INSAT-3DR TIR-1 imagery confirm intense "
            f"convective storm activity. Topographical DEM simulation projects peak street inundation of "
            f"{simulation_steps[2]['depth']}m across {', '.join(city['landmarks'][:2])} at T+2h. "
            f"Activate Emergency Operations Center and restrict low-lying underpasses."
        )

        telemetry = {
            "satellite": {
                "source": "INSAT-3DR (MOSDAC / ISRO)",
                "channel": "Thermal Infrared (TIR-1 & Sounder)",
                "cloud_top_temp_kelvin": 201.8,
                "rainfall_hydro_estimator_mm_hr": 72.0
            },
            "radar": {
                "station": city["radar"],
                "reflectivity_dbz": 54.2,
                "echo_top_km": 15.1,
                "radial_velocity_mps": -14.2
            },
            "observational_weather": {
                "station_id": city["aws_id"],
                "sensor_type": "Surface Tipping Bucket AWS (IMD)",
                "current_rainfall_mm_hr": 72.0,
                "cumulative_24h_rainfall_mm": 188.4,
                "relative_humidity_pct": 98.0
            },
            "numerical_weather_prediction": {
                "model_name": "NCMRWF Unified Model / WRF (4km)",
                "forecast_lead_time_hours": 6,
                "predicted_precipitation_mm": 98.0
            }
        }

    else:
        # Clear / Normal Monsoon Day
        alert = "GREEN"
        lead_time = "No Extreme Inundation Threat Detected"
        
        simulation_steps = [
            {
                "t": "T+0h (Nowcast)",
                "depth": 0.02,
                "dbz": 18.0,
                "rain": 1.0,
                "delta": 0.003,
                "sev": "LOW",
                "landmarks": []
            },
            {
                "t": "T+1h",
                "depth": 0.04,
                "dbz": 22.0,
                "rain": 2.5,
                "delta": 0.003,
                "sev": "LOW",
                "landmarks": []
            },
            {
                "t": "T+2h",
                "depth": 0.05,
                "dbz": 20.0,
                "rain": 2.0,
                "delta": 0.003,
                "sev": "LOW",
                "landmarks": []
            },
            {
                "t": "T+3h",
                "depth": 0.01,
                "dbz": 15.0,
                "rain": 0.5,
                "delta": 0.003,
                "sev": "LOW",
                "landmarks": []
            }
        ]

        bulletin = (
            f"IMD NORMAL ADVISORY ({city_key.upper()}): Meteorological indicators show standard regional moisture. "
            f"No convective cloudburst or road inundation conditions detected."
        )

        telemetry = {
            "satellite": {
                "source": "INSAT-3DR (MOSDAC / ISRO)",
                "channel": "Thermal Infrared (TIR-1)",
                "cloud_top_temp_kelvin": 265.0,
                "rainfall_hydro_estimator_mm_hr": 2.5
            },
            "radar": {
                "station": city["radar"],
                "reflectivity_dbz": 22.0,
                "echo_top_km": 4.0,
                "radial_velocity_mps": -2.1
            },
            "observational_weather": {
                "station_id": city["aws_id"],
                "sensor_type": "Surface Tipping Bucket AWS (IMD)",
                "current_rainfall_mm_hr": 1.5,
                "cumulative_24h_rainfall_mm": 10.0,
                "relative_humidity_pct": 68.0
            },
            "numerical_weather_prediction": {
                "model_name": "NCMRWF Unified Model / WRF (4km)",
                "forecast_lead_time_hours": 6,
                "predicted_precipitation_mm": 4.0
            }
        }

    # 3. Build Animation Simulation Frames
    frames = []
    for s in simulation_steps:
        poly = build_geojson_polygon(lon, lat, s["delta"])
        frames.append(InundationFrame(
            time_step=s["t"],
            water_depth_meters=s["depth"],
            radar_dbz=s["dbz"],
            satellite_rain_rate_mm_hr=s["rain"],
            severity=s["sev"],
            affected_landmarks=s["landmarks"],
            geojson_geometry=poly
        ))

    # 4. Extract Peak Inundation for the standard polygon view
    peak_step = simulation_steps[2] if alert == "RED" else simulation_steps[0]
    peak_zones = []
    if alert == "RED":
        peak_zones = [
            InundationPolygon(
                zone_id=f"INUND-PEAK-{city_key[:3].upper()}-01",
                severity="CRITICAL",
                avg_water_depth_meters=peak_step["depth"],
                affected_landmarks=city["landmarks"],
                geojson_geometry=build_geojson_polygon(lon, lat, peak_step["delta"])
            )
        ]

    return PS71SimulationResponse(
        timestamp=now,
        district=city_key,
        lead_time_warning=lead_time,
        alert_level=alert,
        meteorological_inputs=telemetry,
        inundation_zones=peak_zones,
        simulation_frames=frames,
        advisory_bulletin=bulletin
    )


# --- Dedicated Route Handlers with Unique Operation IDs ---

@router.get("/predict", response_model=PS71SimulationResponse, operation_id="predict_inundation_endpoint")
async def predict_inundation(
    district: str = Query("Mumbai", description="Select city: Mumbai, Delhi, Chennai, Kolkata, Guwahati, Ernakulam"),
    scenario: str = Query("EXTREME_EVENT", description="Toggle 'NORMAL' or 'EXTREME_EVENT'")
):
    return await _execute_inundation_pipeline(district, scenario)


@router.get("/simulate", response_model=PS71SimulationResponse, operation_id="simulate_inundation_endpoint")
async def simulate_inundation(
    district: str = Query("Mumbai", description="Select city: Mumbai, Delhi, Chennai, Kolkata, Guwahati, Ernakulam"),
    scenario: str = Query("EXTREME_EVENT", description="Toggle 'NORMAL' or 'EXTREME_EVENT'")
):
    return await _execute_inundation_pipeline(district, scenario)


@router.get("/heavy-rainfall/predict", response_model=PS71SimulationResponse, operation_id="predict_heavy_rainfall_endpoint")
async def predict_heavy_rainfall(
    district: str = Query("Mumbai", description="Select city: Mumbai, Delhi, Chennai, Kolkata, Guwahati, Ernakulam"),
    scenario: str = Query("EXTREME_EVENT", description="Toggle 'NORMAL' or 'EXTREME_EVENT'")
):
    return await _execute_inundation_pipeline(district, scenario)