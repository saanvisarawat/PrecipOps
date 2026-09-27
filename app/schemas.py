from pydantic import BaseModel, ConfigDict
from typing import Optional, List, Dict, Any, Literal
from datetime import datetime

from .models import UserRole

class ReportCreate(BaseModel):
    description: str
    latitude: float
    longitude: float
    # user_id removed so the Flutter app does not throw 422 errors

class ReportVerify(BaseModel):
    is_verified: bool

class UserCreate(BaseModel):
    full_name: str
    email: str
    password: str
    # Must match models.UserRole exactly (citizen/volunteer/official) — the
    # register screen lets a user pick any of the three, and the frontend
    # sends that literal role string.
    role: Literal["citizen", "volunteer", "official"] = "citizen"

class UserLogin(BaseModel):
    email: str
    password: str

class BulkReportItem(BaseModel):
    description: str
    latitude: float
    longitude: float
    client_timestamp: datetime

class BulkReportUpload(BaseModel):
    reports: List[BulkReportItem]

class RiskPredictionRequest(BaseModel):
    # Features required by the trained XGBoost flood risk engine
    # Default values provided to simulate a true "Severe" 4-pillar consensus event
    om_rainfall_mm: float = 185.0
    om_river_discharge: float = 950.0
    om_rainfall_mm_15d_sum: float = 450.0
    srtm_elevation_m: float = 4.5
    srtm_slope_deg: float = 0.2
    aws_rainfall_mm: float = 180.0
    sat_precipitation_mm: float = 190.0
    nwp_precipitation_sum: float = 420.0
    consensus_rainfall_mm: float = 185.0
    consensus_rainfall_sources: float = 4.0
    historical_flood_count: float = 14.0

class ChatRequest(BaseModel):
    message: str
    session_id: str = "default"
    language: str = "english"  # Triggers Malayalam translation

class VolunteerLocationUpdate(BaseModel):
    latitude: float
    longitude: float
    status: str = "available"  # available / busy / offline
    skills: Optional[str] = None  # e.g., "boat,medical,swimming"

class PredictionResponse(BaseModel):
    id: int
    district: str
    risk_class: int
    
    model_config = ConfigDict(from_attributes=True)

class AlertResponse(BaseModel):
    id: int
    district: str
    alert_level: str
    message: str
    status: str = "pending"
    risk_score: Optional[int] = None
    created_at: datetime
    resolved_by: Optional[int] = None
    resolved_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)

class ReportAdminResponse(BaseModel):
    id: int
    description: str
    latitude: float
    longitude: float
    status: str
    yes_count: int
    no_count: int
    client_timestamp: Optional[datetime] = None
    assigned_volunteer_id: Optional[int] = None
    assigned_volunteer_name: Optional[str] = None

class VolunteerAdminResponse(BaseModel):
    id: int
    full_name: str
    status: str
    skills: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None

class AssignReportRequest(BaseModel):
    volunteer_id: int

class AgentRunLogResponse(BaseModel):
    id: int
    run_id: str
    district: str
    status: str
    coordinator_summary: str
    execution_chain: List[Dict[str, Any]]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

# --- INUNDATION & PS71 TELEMETRY SCHEMAS ---

class InundationPolygon(BaseModel):
    zone_id: str
    severity: str  # "MODERATE", "CRITICAL", "EXTREME"
    avg_water_depth_meters: float
    affected_landmarks: List[str]
    geojson_geometry: Dict[str, Any]

class PS71PredictionResponse(BaseModel):
    timestamp: str
    district: str
    lead_time_warning: str
    alert_level: str  # "GREEN", "ORANGE", "RED"
    meteorological_inputs: Dict[str, Any]
    inundation_zones: List[InundationPolygon]
    advisory_bulletin: str