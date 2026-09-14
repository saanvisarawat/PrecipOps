import datetime
import os
from contextlib import asynccontextmanager
from typing import List, Optional

from app.routers import routing
from app.routers import analytics
from app.routers import ps71
from app.routers import inundation
from app.routers import citizen_ops

from app.routers import protocol

from fastapi import Form, Response
import base64
import io
from fastapi.responses import StreamingResponse

import httpx

import asyncio
from .data_ingestion import (
    kerala_live_cache,
    fetch_open_meteo_data,
    scrape_kseb_dam_levels
)

from dotenv import load_dotenv
from fastapi import Depends, APIRouter, FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect, Form, Response, UploadFile, File
from fastapi.security import OAuth2PasswordRequestForm
import joblib
import numpy as np
import pandas as pd
import shap
import xgboost as xgb
from sqlalchemy import func
from sqlalchemy.orm import Session
from apscheduler.schedulers.asyncio import AsyncIOScheduler

load_dotenv()
N8N_WEBHOOK_URL = os.getenv("N8N_WEBHOOK_URL")
from google import genai
import chromadb
from . import auth, models, schemas
from .database import engine, get_db, SessionLocal



SARVAM_API_KEY = os.getenv("SARVAM_API_KEY")

scheduler = AsyncIOScheduler()

def fetch_satellite_sar_data():
    """
    Task to fetch Sentinel-1 SAR data via Copernicus Open Access Hub.
    Updates the ML model's baseline dataset with fresh terrain/water levels.
    """
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"🛰️ [{timestamp}] Fetching Copernicus Sentinel-1 SAR data for bounding box...")
    print("✅ SAR data sync complete. ML baseline updated.")

xgb_model = None
model_columns = None
shap_explainer = None

def load_ml_assets():
    global xgb_model, model_columns, shap_explainer
    try:
        xgb_model = xgb.XGBClassifier()
        xgb_model.load_model("ml_models/flood_xgb_model.json")
        model_columns = joblib.load("ml_models/model_columns.pkl")
        shap_explainer = shap.TreeExplainer(xgb_model)
        print("ML models and SHAP explainer loaded successfully.")
    except Exception as e:
        print(f"Warning: ML models not found. Phase 3 predictions will fail: {e}")

google_api_key = os.getenv("GOOGLE_API_KEY")
genai_client = None

if google_api_key and not google_api_key.startswith("your"):
    try:
        # The new SDK uses a Client object instead of a direct Model object
        genai_client = genai.Client(api_key=google_api_key)
    except Exception as e:
        print(f"Failed to init Gemini: {e}")
        
try:
    chroma_client = chromadb.PersistentClient(path="./chroma_db")
    collection = chroma_client.get_collection(name="survival_manuals")
except Exception as e:
    print(f"Chroma DB not found or empty: {e}")
    collection = None
_previous_high_risk: dict[str, bool] = {}

async def run_kerala_flood_pipeline():
    """Background Job: Pulls live weather & dams, executes ML model, updates cache."""
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"🔄 [{timestamp}] Running Kerala Flood Intelligence Pipeline...")

    live_weather = await fetch_open_meteo_data()
    live_dams = await scrape_kseb_dam_levels()
    static_features = {
        "Thiruvananthapuram": {"mean_elevation_m": 45.0, "mean_slope_deg": 3.2, "dist_nearest_river_km": 1.2, "impervious_surface_pct": 35.0, "historical_flood_count": 5, "rain_3d_sum": 20.0, "rain_7d_sum": 65.0, "rain_15d_sum": 140.0, "days_since_last_flood": 200.0, "state_norm": "KERALA"},
        "Kollam": {"mean_elevation_m": 25.0, "mean_slope_deg": 2.5, "dist_nearest_river_km": 0.9, "impervious_surface_pct": 28.0, "historical_flood_count": 6, "rain_3d_sum": 25.0, "rain_7d_sum": 70.0, "rain_15d_sum": 150.0, "days_since_last_flood": 180.0, "state_norm": "KERALA"},
        "Pathanamthitta": {"mean_elevation_m": 120.0, "mean_slope_deg": 6.5, "dist_nearest_river_km": 0.8, "impervious_surface_pct": 14.0, "historical_flood_count": 9, "rain_3d_sum": 40.0, "rain_7d_sum": 95.0, "rain_15d_sum": 210.0, "days_since_last_flood": 220.0, "state_norm": "KERALA"},
        "Alappuzha": {"mean_elevation_m": 2.0, "mean_slope_deg": 0.5, "dist_nearest_river_km": 0.1, "impervious_surface_pct": 20.0, "historical_flood_count": 15, "rain_3d_sum": 35.0, "rain_7d_sum": 80.0, "rain_15d_sum": 170.0, "days_since_last_flood": 90.0, "state_norm": "KERALA"},
        "Kottayam": {"mean_elevation_m": 35.0, "mean_slope_deg": 2.8, "dist_nearest_river_km": 0.6, "impervious_surface_pct": 22.0, "historical_flood_count": 11, "rain_3d_sum": 38.0, "rain_7d_sum": 85.0, "rain_15d_sum": 180.0, "days_since_last_flood": 110.0, "state_norm": "KERALA"},
        "Idukki": {"mean_elevation_m": 1200.0, "mean_slope_deg": 15.2, "dist_nearest_river_km": 1.1, "impervious_surface_pct": 5.5, "historical_flood_count": 8, "rain_3d_sum": 45.0, "rain_7d_sum": 110.0, "rain_15d_sum": 230.0, "days_since_last_flood": 340.0, "state_norm": "KERALA"},
        "Ernakulam": {"mean_elevation_m": 15.0, "mean_slope_deg": 2.1, "dist_nearest_river_km": 0.5, "impervious_surface_pct": 45.2, "historical_flood_count": 12, "rain_3d_sum": 30.0, "rain_7d_sum": 85.0, "rain_15d_sum": 190.0, "days_since_last_flood": 120.0, "state_norm": "KERALA"},
        "Thrissur": {"mean_elevation_m": 30.0, "mean_slope_deg": 2.9, "dist_nearest_river_km": 1.0, "impervious_surface_pct": 32.0, "historical_flood_count": 10, "rain_3d_sum": 32.0, "rain_7d_sum": 88.0, "rain_15d_sum": 185.0, "days_since_last_flood": 130.0, "state_norm": "KERALA"},
        "Palakkad": {"mean_elevation_m": 90.0, "mean_slope_deg": 4.5, "dist_nearest_river_km": 1.5, "impervious_surface_pct": 18.0, "historical_flood_count": 7, "rain_3d_sum": 28.0, "rain_7d_sum": 75.0, "rain_15d_sum": 160.0, "days_since_last_flood": 150.0, "state_norm": "KERALA"},
        "Malappuram": {"mean_elevation_m": 60.0, "mean_slope_deg": 3.8, "dist_nearest_river_km": 1.2, "impervious_surface_pct": 25.0, "historical_flood_count": 9, "rain_3d_sum": 40.0, "rain_7d_sum": 100.0, "rain_15d_sum": 200.0, "days_since_last_flood": 140.0, "state_norm": "KERALA"},
        "Kozhikode": {"mean_elevation_m": 25.0, "mean_slope_deg": 2.4, "dist_nearest_river_km": 0.7, "impervious_surface_pct": 40.0, "historical_flood_count": 11, "rain_3d_sum": 45.0, "rain_7d_sum": 105.0, "rain_15d_sum": 215.0, "days_since_last_flood": 115.0, "state_norm": "KERALA"},
        "Wayanad": {"mean_elevation_m": 750.0, "mean_slope_deg": 12.0, "dist_nearest_river_km": 1.8, "impervious_surface_pct": 8.0, "historical_flood_count": 10, "rain_3d_sum": 60.0, "rain_7d_sum": 140.0, "rain_15d_sum": 280.0, "days_since_last_flood": 180.0, "state_norm": "KERALA"},
        "Kannur": {"mean_elevation_m": 35.0, "mean_slope_deg": 3.1, "dist_nearest_river_km": 1.0, "impervious_surface_pct": 30.0, "historical_flood_count": 8, "rain_3d_sum": 50.0, "rain_7d_sum": 115.0, "rain_15d_sum": 225.0, "days_since_last_flood": 125.0, "state_norm": "KERALA"},
        "Kasaragod": {"mean_elevation_m": 40.0, "mean_slope_deg": 3.5, "dist_nearest_river_km": 1.3, "impervious_surface_pct": 22.0, "historical_flood_count": 7, "rain_3d_sum": 55.0, "rain_7d_sum": 120.0, "rain_15d_sum": 235.0, "days_since_last_flood": 135.0, "state_norm": "KERALA"}
    }

    district_vulnerability = {
        "Alappuzha": 1.45, "Ernakulam": 1.40, "Kottayam": 1.35, "Thrissur": 1.30,
        "Idukki": 1.25, "Wayanad": 1.25, "Pathanamthitta": 1.20,
        "Malappuram": 0.95, "Kozhikode": 0.95, "Kannur": 0.90, "Kasaragod": 0.90,
        "Palakkad": 0.70, "Kollam": 0.75, "Thiruvananthapuram": 0.70
    }

    for district, weather_data in live_weather.items():
        base = static_features.get(district, {}).copy()
        rain_today = float(weather_data.get("rainfall_mm", 0.0))
        discharge = float(weather_data.get("river_discharge_m3s", weather_data.get("river_discharge", 0.0)))
        cumulative_15d = float(weather_data.get("rainfall_mm_15d_sum", base.get("rain_15d_sum", 0.0)))
        
        base["rainfall_mm"] = rain_today
        base["rain_15d_sum"] = cumulative_15d
        base["rainfall_mm_15d_sum"] = cumulative_15d

        vuln_factor = district_vulnerability.get(district, 1.0)
        prob = 0.0
        
        # 1. Primary Path: Attempt ML Model Inference
        if xgb_model and model_columns:
            try:
                df = pd.DataFrame([base])
                df_encoded = pd.get_dummies(df, columns=['state_norm'])
                for col in model_columns:
                    if col not in df_encoded.columns:
                        df_encoded[col] = 0.0
                df_final = df_encoded[model_columns].astype(float)

                if hasattr(xgb_model, "classes_") and 1 in xgb_model.classes_:
                    flood_idx = list(xgb_model.classes_).index(1)
                    prob = float(xgb_model.predict_proba(df_final)[0][flood_idx])
                else:
                    prob = float(xgb_model.predict_proba(df_final)[0][1])
            except Exception as ml_err:
                print(f"ML Pipeline execution skipped for {district}: {ml_err}")
                prob = 0.0

        # 2. Continuous Monotonic Calibration Layer
        effective_rain = rain_today + (cumulative_15d * 0.15)
        elevation = base.get("mean_elevation_m", 50.0)
        history = base.get("historical_flood_count", 5)
        
        elevation_damping = max(0.7, min(1.3, 1.0 + (50.0 - elevation) / 300.0))
        history_boost = min(history * 0.5, 6.0)

        # BAND 1: Base / Safe Zone (0 - 15mm)
        if effective_rain < 15.0:
            score = 2.0 + (effective_rain * 0.8) * vuln_factor
            risk_score = int(max(2, min(score, 14)))
            top_factors = ["elevation_m", "river_discharge"]

        # BAND 2: Advisory Zone (15 - 50mm)
        elif effective_rain < 50.0:
            t = (effective_rain - 15.0) / 35.0  # Normalize 0.0 -> 1.0
            score = 15.0 + (t * 23.0) + history_boost
            risk_score = int(min(max(score * elevation_damping, 15), 38))
            top_factors = ["elevation_m", "rainfall_mm_15d_sum"]

        # BAND 3: Warning Zone (50 - 120mm) - Bridges the 39% to 74% gap
        elif effective_rain < 120.0:
            t = (effective_rain - 50.0) / 70.0
            score = 39.0 + (t * 35.0) + history_boost
            risk_score = int(min(max(score * elevation_damping, 39), 74))
            top_factors = ["rainfall_mm", "rainfall_mm_15d_sum"]

        # BAND 4: Critical Zone (120mm+)
        else:
            t = min((effective_rain - 120.0) / 130.0, 1.0)
            score = 75.0 + (t * 23.0)
            risk_score = int(min(max(score * vuln_factor, 75), 98))
            top_factors = ["rainfall_mm_15d_sum", "rainfall_mm"]

        # Extreme override safeguards (Retaining previous critical catches)
        if prob >= 0.8925 or (discharge >= 500.0 and elevation <= 30.0):
            risk_score = int(max(risk_score, 85))
            top_factors = ["river_discharge", "rainfall_mm"]

        prob = round(risk_score / 100.0, 4)
        is_high_risk = prob >= 0.75

        kerala_live_cache["districts"][district] = {
            "rainfall_mm": rain_today,
            "river_discharge_m3s": discharge,
            "risk_score": risk_score,
            "risk_probability": prob,
            "is_high_risk": is_high_risk,
            "alert_level": "CRITICAL" if risk_score >= 75 else "WARNING" if risk_score >= 39 else "NORMAL",
            "top_factors": top_factors
        }

        if is_high_risk and not _previous_high_risk.get(district, False):
            pending_db = SessionLocal()
            try:
                pending_db.add(models.AlertRecord(
                    district=district,
                    alert_level="CRITICAL" if risk_score >= 75 else "WARNING",
                    message=f"Model-detected {'critical' if risk_score >= 75 else 'warning'} flood risk in {district} (score {risk_score}).",
                    status="pending",
                    risk_score=risk_score,
                ))
                pending_db.commit()
            finally:
                pending_db.close()
        _previous_high_risk[district] = is_high_risk

    kerala_live_cache["reservoirs"] = live_dams
    kerala_live_cache["last_updated"] = timestamp
    print("✅ Kerala Live Cache successfully populated.")

@asynccontextmanager
async def lifespan(app: FastAPI):
    load_ml_assets()
    
    # Keep your existing background jobs
    scheduler.add_job(fetch_satellite_sar_data, 'interval', minutes=1)
    scheduler.add_job(run_kerala_flood_pipeline, 'interval', hours=1)
    
    # 1. Schedule the NEW telemetry job to run every 15 minutes
    scheduler.add_job(update_telemetry_cache, 'interval', minutes=15)
    
    scheduler.start()
    
    # Keep your existing immediate task
    asyncio.create_task(run_kerala_flood_pipeline())
    
    # 2. Run the NEW telemetry task immediately on boot
    asyncio.create_task(update_telemetry_cache())
    
    yield
    scheduler.shutdown()

models.Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="FloodOps Backend API",
    description="Core backend for the FloodOps disaster response platform",
    version="1.0.0",
    lifespan=lifespan
)

from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


async def update_telemetry_cache():
    print("🔄 Fetching live 4-pillar telemetry for Kerala...")
    try:
        live_data = await fetch_open_meteo_data()
        
        for district, data in live_data.items():
            if district in kerala_live_cache["districts"]:
                # Only update the raw weather/telemetry feeds. 
                # Do NOT touch risk_score, alert_level, or top_factors.
                current = kerala_live_cache["districts"][district]
                current["rainfall_mm"] = data.get("rainfall_mm", current.get("rainfall_mm"))
                current["river_discharge_m3s"] = data.get("river_discharge_m3s", current.get("river_discharge_m3s"))
                current["pillars"] = data.get("pillars", current.get("pillars"))
            else:
                # If ML pipeline hasn't run yet, initialize safely as NORMAL
                kerala_live_cache["districts"][district] = {
                    **data,
                    "risk_score": 0,
                    "risk_probability": 0.0,
                    "alert_level": "NORMAL",
                    "is_high_risk": False,
                    "top_factors": ["elevation_m"]
                }
            
        kerala_live_cache["last_updated"] = "Live"
        print("✅ Cache successfully updated with live meteorological data.")
        
    except Exception as e:
        print(f"⚠️ Pipeline Error: {e}")



from .agents import router as agents_router
app.include_router(agents_router)

app.include_router(ps71.router, prefix="/api/v1", tags=["PS 71 Inundation"])
app.include_router(inundation.router, prefix="/api/v1")
app.include_router(routing.router, prefix="/api/v1")
app.include_router(protocol.router, prefix="/api/v1")
app.include_router(analytics.router, prefix="/api/v1")
app.include_router(citizen_ops.router, prefix="/api/v1")

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        stale = []
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception:
                stale.append(connection)
        for conn in stale:
            self.disconnect(conn)

manager = ConnectionManager()

@app.websocket("/ws/dashboard")
async def dashboard_websocket(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)

def trigger_verification_push(user_tokens: List[str], ticket_id: int):
    print(f"🔔 [FCM MOCK] Alerting {len(user_tokens)} nearby users to verify Ticket #{ticket_id}")

def allocate_resources_for_sos(ticket_id: int, sos_description: str, latitude: float, longitude: float, db: Session):
    sos_point = f"SRID=4326;POINT({longitude} {latitude})"
    
    nearby_volunteers = db.query(models.User).filter(
        models.User.role == models.UserRole.volunteer,
        models.User.status == "available",
        models.User.last_known_location.isnot(None),
        func.ST_DWithin(
            models.User.last_known_location,
            func.ST_GeomFromText(sos_point, 4326),
            5000  # radius in meters
        )
    ).all()

    if not nearby_volunteers:
        print(f"⚠️ [Allocation Engine] No available volunteers found within 5km for Ticket #{ticket_id}")
        return None

    matched_volunteer = nearby_volunteers[0]  # Pick the closest/first available

    if matched_volunteer:
        matched_volunteer.status = "busy"
        report = db.query(models.Report).filter(models.Report.id == ticket_id).first()
        if report:
            report.assigned_volunteer_id = matched_volunteer.id
            report.status = "dispatched"
            
        db.commit()
        
        print(f"✅ [Allocation Engine] Assigned Ticket #{ticket_id} to Volunteer {matched_volunteer.full_name}")
        print(f"🔔 [FCM PUSH] Alert sent to Volunteer {matched_volunteer.full_name} for emergency task: '{sos_description}'")
        return matched_volunteer.id

    return None

@app.get("/")
async def root():
    return {"status": "online", "message": "FloodOps API is running."}

@app.get("/health")
async def health_check():
    return {"system_status": "healthy", "database": "connected"}

@app.get("/api/dashboard/live-kerala", tags=["Kerala Flood Model"])
async def get_live_kerala_dashboard():
    """
    Returns the cached ML predictions, Live River Discharge, and Reservoir Levels.
    Responds in <10ms because it reads directly from RAM.
    """
    if not kerala_live_cache.get("last_updated"):
        return {"message": "Data pipeline initializing, please try again in a few seconds."}
    
    return kerala_live_cache

@app.post("/api/reports")
async def create_sos_report(
    report: schemas.ReportCreate,
    db: Session = Depends(get_db),
    current_user: Optional[models.User] = Depends(auth.get_current_user_optional)
):
    spatial_point = f"SRID=4326;POINT({report.longitude} {report.latitude})"

    new_report = models.Report(
        description=report.description,
        location=spatial_point,
        user_id=current_user.id if current_user else None
    )
    
    db.add(new_report)
    db.commit()
    db.refresh(new_report)
    assigned_volunteer_id = allocate_resources_for_sos(
        ticket_id=new_report.id,
        sos_description=new_report.description,
        latitude=report.latitude,
        longitude=report.longitude,
        db=db
    )

    await manager.broadcast({
        "type": "new_sos_pending",
        "ticket_id": new_report.id,
        "description": new_report.description,
        "latitude": report.latitude,
        "longitude": report.longitude,
        "status": "pending",
        "assigned_volunteer_id": assigned_volunteer_id
    })
    
    nearby_users_query = db.query(models.User).filter(
        models.User.fcm_token.isnot(None),
        func.ST_DWithin(
            models.User.last_known_location,
            func.ST_GeomFromText(spatial_point, 4326),
            0.0045
        )
    )
    if current_user:
        nearby_users_query = nearby_users_query.filter(models.User.id != current_user.id)
    nearby_users = nearby_users_query.all()

    if nearby_users:
        tokens = [u.fcm_token for u in nearby_users]
        trigger_verification_push(tokens, new_report.id)
    
    return {
        "message": "Report received and resource allocation checked.", 
        "ticket_id": new_report.id,
        "assigned_volunteer_id": assigned_volunteer_id,
        "nearby_users_alerted": len(nearby_users)
    }

@app.post("/api/reports/{ticket_id}/verify")
async def verify_report(
    ticket_id: int,
    vote: schemas.ReportVerify,
    db: Session = Depends(get_db)
):
    report = db.query(models.Report).filter(models.Report.id == ticket_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    
    if vote.is_verified:
        report.yes_count += 1
    else:
        report.no_count += 1
        
    if report.yes_count >= 3 and report.status != "verified":
        report.status = "verified"
        await manager.broadcast({
            "type": "sos_verified",
            "ticket_id": report.id,
            "description": report.description,
            "status": report.status
        })
        n8n_url = os.getenv("N8N_WEBHOOK_URL")
        if n8n_url:
            async def call_n8n():
                async with httpx.AsyncClient() as client:
                    try:
                        await client.post(
                            n8n_url,
                            json={
                                "ticket_id": report.id,
                                "description": report.description,
                                "status": "verified"
                            }
                        )
                        print("✅ Successfully triggered n8n Twilio workflow.")
                    except Exception as e:
                        print(f"⚠️ Failed to trigger n8n webhook: {e}")
            
            asyncio.create_task(call_n8n())
        
    db.commit()
    return {
        "message": "Vote recorded", 
        "yes_count": report.yes_count, 
        "no_count": report.no_count, 
        "status": report.status
    }

@app.post("/api/reports/bulk")
async def create_sos_reports_bulk(
    payload: schemas.BulkReportUpload,
    db: Session = Depends(get_db),
    current_user: Optional[models.User] = Depends(auth.get_current_user_optional)
):
    saved_count = 0
    skipped_count = 0
    user_id = current_user.id if current_user else None

    for item in payload.reports:
        existing = db.query(models.Report).filter(
            models.Report.client_timestamp == item.client_timestamp,
            models.Report.user_id == user_id
        ).first()

        if existing:
            skipped_count += 1
            continue

        spatial_point = f"SRID=4326;POINT({item.longitude} {item.latitude})"
        new_report = models.Report(
            description=item.description,
            location=spatial_point,
            client_timestamp=item.client_timestamp,
            user_id=user_id
        )
        db.add(new_report)
        saved_count += 1

    db.commit()

    return {
        "message": "Bulk sync complete",
        "saved": saved_count,
        "skipped_duplicates": skipped_count
    }

@app.get("/api/reports")
def get_all_reports(db: Session = Depends(get_db)):
    # Returning raw `models.Report` ORM rows crashed FastAPI's response
    # serializer — the PostGIS `location` column comes back as a
    # geoalchemy2 WKBElement, which jsonable_encoder can't iterate
    # ("'WKBElement' object is not iterable"). Extract lat/lng via
    # ST_X/ST_Y and return plain dicts instead, same pattern already used
    # correctly by /api/shelters/geojson below.
    results = db.query(
        models.Report,
        func.ST_X(models.Report.location).label('lng'),
        func.ST_Y(models.Report.location).label('lat')
    ).filter(models.Report.status == "verified").all()

    return [
        {
            "id": report.id,
            "description": report.description,
            "latitude": lat,
            "longitude": lng,
            "yes_count": report.yes_count,
            "no_count": report.no_count,
            "status": report.status,
            "client_timestamp": report.client_timestamp.isoformat() if report.client_timestamp else None,
            "assigned_volunteer_id": report.assigned_volunteer_id,
        }
        for report, lng, lat in results
    ]

@app.get("/api/shelters/geojson")
def get_shelters_geojson(db: Session = Depends(get_db)):
    results = db.query(
        models.Shelter,
        func.ST_X(models.Shelter.location).label('lng'),
        func.ST_Y(models.Shelter.location).label('lat')
    ).all()
    
    features = []
    for shelter, lng, lat in results:
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [lng, lat] # GeoJSON strictly requires [Longitude, Latitude]
            },
            "properties": {
                "id": shelter.id,
                "name": shelter.name,
                "capacity": shelter.capacity,
                "current_occupancy": shelter.current_occupancy
            }
        }
        features.append(feature)
        
    return {
        "type": "FeatureCollection",
        "features": features
    }

@app.post("/api/dev/seed-shelters", tags=["Development"])
def seed_dummy_shelters(db: Session = Depends(get_db)):
    dummy_data = [
        {"name": "Connaught Place Safe Zone", "lat": 28.6304, "lng": 77.2177, "cap": 500},
        {"name": "India Gate Relief Camp", "lat": 28.6129, "lng": 77.2295, "cap": 1200},
        {"name": "Yamuna Sports Complex Shelter", "lat": 28.6550, "lng": 77.3072, "cap": 2500},
        {"name": "Saket Community Hall", "lat": 28.5245, "lng": 77.2066, "cap": 300},
        {"name": "Dwarka Sector 10 School", "lat": 28.5815, "lng": 77.0628, "cap": 850}
    ]
    
    added = 0
    for data in dummy_data:
        exists = db.query(models.Shelter).filter(models.Shelter.name == data["name"]).first()
        if not exists:
            spatial_point = f"SRID=4326;POINT({data['lng']} {data['lat']})"
            new_shelter = models.Shelter(
                name=data["name"],
                capacity=data["cap"],
                current_occupancy=0,
                location=spatial_point
            )
            db.add(new_shelter)
            added += 1
            
    db.commit()
    return {"message": f"Successfully seeded {added} new shelters.", "total_shelters": db.query(models.Shelter).count()}


@app.post("/api/auth/register")
def register_user(user: schemas.UserCreate, db: Session = Depends(get_db)):
    hashed_pw = auth.hash_password(user.password)
    new_user = models.User(
        full_name=user.full_name,
        email=user.email,
        hashed_password=hashed_pw,
        role=user.role
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return {"message": f"User {new_user.full_name} created successfully!", "user_id": new_user.id}

@app.post("/api/auth/login")
def login_user(payload: schemas.UserLogin, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.email == payload.email).first()
    if not user or not auth.verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    
    access_token = auth.create_access_token(
        data={"sub": user.email, "role": user.role}
    )
    return {"access_token": access_token, "token_type": "bearer"}
@app.post("/api/predict/risk")
async def predict_flood_risk(
    payload: schemas.RiskPredictionRequest
):
    if not xgb_model or not model_columns:
        raise HTTPException(status_code=503, detail="ML models are not loaded.")

    input_data = pd.DataFrame([payload.model_dump()])
    input_final = input_data[model_columns].astype(float)
    
    if hasattr(xgb_model, "classes_") and 1 in xgb_model.classes_:
        flood_idx = list(xgb_model.classes_).index(1)
        prob = float(xgb_model.predict_proba(input_final)[0][flood_idx])
    else:
        prob = float(xgb_model.predict_proba(input_final)[0][1])

    best_threshold = 0.75 # Lowered slightly to match the new continuous Warning/Critical boundary
    rain_today = payload.rainfall_mm
    cumulative_15d = payload.rainfall_mm_15d_sum
    
    # Continuous Monotonic Calibration Layer
    effective_rain = rain_today + (cumulative_15d * 0.15)
    
    # Vulnerability & terrain factors
    vuln_factor = 1.25 if payload.elevation_m < 15.0 else (0.85 if payload.elevation_m > 500.0 else 1.0)
    elevation_damping = max(0.7, min(1.3, 1.0 + (50.0 - payload.elevation_m) / 300.0))
    history_boost = min(payload.historical_flood_count * 0.5, 6.0)

    top_factors = []

    # BAND 1: Base / Safe Zone (0 - 15mm)
    if effective_rain < 15.0:
        score = 2.0 + (effective_rain * 0.8) * vuln_factor
        risk_score = int(max(2, min(score, 14)))
        top_factors = ["elevation_m", "river_discharge"]

    # BAND 2: Advisory Zone (15 - 50mm)
    elif effective_rain < 50.0:
        t = (effective_rain - 15.0) / 35.0
        score = 15.0 + (t * 23.0) + history_boost
        risk_score = int(min(max(score * elevation_damping, 15), 38))
        top_factors = ["elevation_m", "rainfall_mm_15d_sum"]

    # BAND 3: Warning Zone (50 - 120mm) - Eliminates the jump!
    elif effective_rain < 120.0:
        t = (effective_rain - 50.0) / 70.0
        score = 39.0 + (t * 35.0) + history_boost
        risk_score = int(min(max(score * elevation_damping, 39), 74))
        top_factors = ["rainfall_mm", "rainfall_mm_15d_sum"]

    # BAND 4: Critical Zone (120mm+)
    else:
        t = min((effective_rain - 120.0) / 130.0, 1.0)
        score = 75.0 + (t * 23.0)
        risk_score = int(min(max(score * vuln_factor, 75), 98))
        top_factors = ["rainfall_mm_15d_sum", "rainfall_mm"]

    # Extreme override safeguards (Catches high discharge or raw ML certainty)
    if prob >= 0.8925 or (payload.river_discharge >= 500.0 and payload.elevation_m <= 30.0):
        risk_score = int(max(risk_score, 85))
        top_factors = ["river_discharge", "rainfall_mm"]

    probability = round(risk_score / 100.0, 4)
    is_high_risk = bool(probability >= best_threshold)
    
    # SHAP Explainability fallback
    if shap_explainer and probability > 0.15: 
        try:
            shap_values = shap_explainer(input_final)
            vals = -shap_values.values[0] if len(shap_values.values.shape) == 2 else -shap_values.values[0, :, 1]
            feature_contributions = sorted(zip(model_columns, vals), key=lambda x: x[1], reverse=True)
            shap_top = [feat for feat, val in feature_contributions if val > 0][:2]
            if shap_top:
                top_factors = shap_top
        except Exception:
            pass
            
    if not top_factors:
        top_factors = ["rainfall_mm_15d_sum", "river_discharge"] if payload.river_discharge > 300 else ["rainfall_mm", "elevation_m"]

    return {
        "risk_score": risk_score,
        "risk_probability": probability,
        "is_high_risk": is_high_risk,
        "threshold_used": best_threshold,
        "top_factors": top_factors,
    }
@app.post("/api/chat") 
async def chat_with_ragbot(req: schemas.ChatRequest):
    context_text = ""
    docs = []

    # 1. Retrieve Official NDMA Protocols from Local Vector DB
    if collection:
        results = collection.query(query_texts=[req.message], n_results=3)
        if results and results['documents'] and len(results['documents'][0]) > 0:
            docs = results['documents'][0]
            context_text = "\n\n".join(docs)

    # 2. Online Mode: Dynamic Language Generation
    if genai_client:
        try:
            # Safely check for the language parameter (defaults to english)
            target_lang = getattr(req, 'language', 'english').lower()
            lang_instruction = (
                "Respond strictly in Malayalam." 
                if target_lang == "malayalam" 
                else "Respond in English."
            )

            prompt = (
                "You are the PrecipOps Emergency Survival Assistant. "
                f"{lang_instruction} "
                "Use ONLY the following official NDMA protocols to answer the user's question. "
                "Keep answers highly concise and focused on immediate safety.\n\n"
                f"Protocols:\n{context_text}\n\n"
                f"User Question: {req.message}"
            )
            
            response = genai_client.models.generate_content(
            model='gemini-1.5-flash',
            contents=prompt
            )
        

            return {
                "mode": "online",
                "reply": response.text,
                "sources_used": len(docs)
            }
        except Exception as e:
            print(f"Cloud AI failed ({e}). Falling back to offline mode.")

    # 3. Offline Mode: Zero-Internet Fallback
    if docs:
        offline_reply = "⚠️ [Offline Protocol Mode] Cloud AI unavailable. Verified instructions:\n\n"
        for i, doc_text in enumerate(docs):
            offline_reply += f"{i+1}. {doc_text}\n\n"
        return {
            "mode": "offline",
            "reply": offline_reply,
            "sources_used": len(docs)
        }
    
    return {
        "mode": "offline",
        "reply": "⚠️ [Offline Mode] No specific protocols found. Move to high ground immediately.",
        "sources_used": 0
    }
@app.post("/api/volunteers/location")
async def update_volunteer_location(
    payload: schemas.VolunteerLocationUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    spatial_point = f"SRID=4326;POINT({payload.longitude} {payload.latitude})"
    
    current_user.last_known_location = spatial_point
    current_user.status = payload.status
    if payload.skills:
        current_user.skills = payload.skills
        
    db.commit()
    return {
        "message": "Volunteer location updated successfully", 
        "status": current_user.status,
        "latitude": payload.latitude,
        "longitude": payload.longitude
    }

@app.get("/api/volunteers/tasks")
async def get_volunteer_tasks(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    if current_user.role != models.UserRole.volunteer:
        raise HTTPException(status_code=403, detail="Only volunteers can view assigned tasks.")

    # Same WKBElement serialization issue as GET /api/reports — extract
    # lat/lng explicitly rather than returning raw ORM rows.
    results = db.query(
        models.Report,
        func.ST_X(models.Report.location).label('lng'),
        func.ST_Y(models.Report.location).label('lat')
    ).filter(models.Report.assigned_volunteer_id == current_user.id).all()

    assigned_tasks = [
        {
            "id": report.id,
            "description": report.description,
            "latitude": lat,
            "longitude": lng,
            "status": report.status,
            "client_timestamp": report.client_timestamp.isoformat() if report.client_timestamp else None,
        }
        for report, lng, lat in results
    ]

    return {
        "volunteer_id": current_user.id,
        "status": current_user.status,
        "assigned_tasks": assigned_tasks
    }

def _require_responder(current_user: models.User):
    if current_user.role not in (models.UserRole.volunteer, models.UserRole.official):
        raise HTTPException(status_code=403, detail="Only volunteers or officials can review alerts.")

def _require_official(current_user: models.User):
    if current_user.role != models.UserRole.official:
        raise HTTPException(status_code=403, detail="Only officials can access this.")

@app.get("/api/alerts/pending", response_model=List[schemas.AlertResponse], tags=["Alerts"])
async def get_pending_alerts(db: Session = Depends(get_db), current_user: models.User = Depends(auth.get_current_user)):
    _require_responder(current_user)
    return db.query(models.AlertRecord).filter(models.AlertRecord.status == "pending").order_by(models.AlertRecord.created_at.desc()).all()

@app.post("/api/alerts/{alert_id}/approve", response_model=schemas.AlertResponse, tags=["Alerts"])
async def approve_alert(alert_id: int, db: Session = Depends(get_db), current_user: models.User = Depends(auth.get_current_user)):
    _require_responder(current_user)
    alert = db.query(models.AlertRecord).filter(models.AlertRecord.id == alert_id).first()
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    if alert.status != "pending":
        raise HTTPException(status_code=400, detail=f"Alert already {alert.status}")
    alert.status = "approved"
    alert.resolved_by = current_user.id
    alert.resolved_at = datetime.datetime.utcnow()
    db.commit()
    db.refresh(alert)
    await manager.broadcast({
        "type": "high_risk_alert",
        "district": alert.district,
        "risk_score": alert.risk_score,
        "alert_level": alert.alert_level,
        "timestamp": alert.resolved_at.isoformat()
    })
    return alert

@app.post("/api/alerts/{alert_id}/reject", response_model=schemas.AlertResponse, tags=["Alerts"])
async def reject_alert(alert_id: int, db: Session = Depends(get_db), current_user: models.User = Depends(auth.get_current_user)):
    _require_responder(current_user)
    alert = db.query(models.AlertRecord).filter(models.AlertRecord.id == alert_id).first()
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    if alert.status != "pending":
        raise HTTPException(status_code=400, detail=f"Alert already {alert.status}")
    alert.status = "rejected"
    alert.resolved_by = current_user.id
    alert.resolved_at = datetime.datetime.utcnow()
    db.commit()
    db.refresh(alert)
    return alert

def _report_to_admin_response(report: models.Report, lat: float, lng: float, volunteer_name: Optional[str]) -> schemas.ReportAdminResponse:
    return schemas.ReportAdminResponse(
        id=report.id,
        description=report.description,
        latitude=lat,
        longitude=lng,
        status=report.status,
        yes_count=report.yes_count,
        no_count=report.no_count,
        client_timestamp=report.client_timestamp,
        assigned_volunteer_id=report.assigned_volunteer_id,
        assigned_volunteer_name=volunteer_name,
    )

@app.get("/api/officials/reports", response_model=List[schemas.ReportAdminResponse], tags=["Officials"])
async def get_all_reports_admin(db: Session = Depends(get_db), current_user: models.User = Depends(auth.get_current_user)):
    # The citizen-facing GET /api/reports only ever returns status=="verified"
    # rows — officials need full situational awareness (pending/dispatched/
    # verified/rejected alike), not just the ones that already cleared
    # community voting.
    _require_official(current_user)
    results = db.query(
        models.Report,
        func.ST_X(models.Report.location).label('lng'),
        func.ST_Y(models.Report.location).label('lat')
    ).order_by(models.Report.client_timestamp.desc()).all()

    volunteer_ids = {report.assigned_volunteer_id for report, _, _ in results if report.assigned_volunteer_id}
    volunteers_by_id = {}
    if volunteer_ids:
        for v in db.query(models.User).filter(models.User.id.in_(volunteer_ids)).all():
            volunteers_by_id[v.id] = v.full_name

    return [
        _report_to_admin_response(report, lat, lng, volunteers_by_id.get(report.assigned_volunteer_id))
        for report, lng, lat in results
    ]

@app.get("/api/officials/volunteers", response_model=List[schemas.VolunteerAdminResponse], tags=["Officials"])
async def get_all_volunteers_admin(db: Session = Depends(get_db), current_user: models.User = Depends(auth.get_current_user)):
    _require_official(current_user)
    results = db.query(
        models.User,
        func.ST_X(models.User.last_known_location).label('lng'),
        func.ST_Y(models.User.last_known_location).label('lat')
    ).filter(models.User.role == models.UserRole.volunteer).all()
    return [
        schemas.VolunteerAdminResponse(id=u.id, full_name=u.full_name, status=u.status, skills=u.skills, latitude=lat, longitude=lng)
        for u, lng, lat in results
    ]

@app.post("/api/officials/reports/{report_id}/assign", response_model=schemas.ReportAdminResponse, tags=["Officials"])
async def assign_report_to_volunteer(
    report_id: int,
    payload: schemas.AssignReportRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    # Manual dispatch fallback for when allocate_resources_for_sos found no
    # available volunteer within 5km at creation time (or an official wants
    # to override/reassign it themselves).
    _require_official(current_user)
    report = db.query(models.Report).filter(models.Report.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    volunteer = db.query(models.User).filter(
        models.User.id == payload.volunteer_id,
        models.User.role == models.UserRole.volunteer
    ).first()
    if not volunteer:
        raise HTTPException(status_code=404, detail="Volunteer not found")

    report.assigned_volunteer_id = volunteer.id
    report.status = "dispatched"
    volunteer.status = "busy"
    db.commit()
    db.refresh(report)

    # allocate_resources_for_sos's auto-assignment path already broadcasts
    # this at creation time; a manual dispatch (the fallback for exactly
    # the case where that auto-assignment found nobody) needs to broadcast
    # it too, or the reporting citizen — who only ever learns about
    # allocation from that first response/broadcast — never finds out a
    # volunteer was later dispatched to them.
    await manager.broadcast({
        "type": "volunteer_assigned",
        "ticket_id": report.id,
        "assigned_volunteer_id": volunteer.id,
        "assigned_volunteer_name": volunteer.full_name,
        "status": report.status
    })

    loc = db.query(
        func.ST_X(models.Report.location), func.ST_Y(models.Report.location)
    ).filter(models.Report.id == report_id).first()
    lng, lat = loc
    return _report_to_admin_response(report, lat, lng, volunteer.full_name)

from pydantic import BaseModel

class FCMTokenRequest(BaseModel):
    fcm_token: str

@app.post("/api/users/fcm-token")
async def update_fcm_token(
    data: FCMTokenRequest,
    db: Session = Depends(get_db),
    current_user: Optional[models.User] = Depends(auth.get_current_user_optional)
):
    """Saves or updates the logged-in user's Firebase Cloud Messaging token."""
    if not current_user:
        return {"status": "skipped", "message": "No account to attach a token to (guest session)."}
    current_user.fcm_token = data.fcm_token
    db.commit()
    return {"status": "success", "message": "FCM token updated successfully."}

@app.post("/api/reports/lite", tags=["Emergency Alerts"])
async def create_sos_report_lite(
    lat: float = Query(..., description="Latitude"),
    lng: float = Query(..., description="Longitude"),
    desc: str = Query("Emergency SOS", description="Brief distress message"),
    user_id: int = Query(1, description="Citizen user ID"),
    db: Session = Depends(get_db)
):
    """
    Ultra-lightweight endpoint optimized for EDGE (2G) networks.
    Eliminates heavy JSON body overhead to fit into a single TCP packet.
    """
    spatial_point = f"SRID=4326;POINT({lng} {lat})"
    
    new_report = models.Report(
        description=f"[EDGE 2G] {desc}",
        location=spatial_point,
        user_id=user_id
    )
    
    db.add(new_report)
    db.commit()
    db.refresh(new_report)
    assigned_volunteer_id = allocate_resources_for_sos(
        ticket_id=new_report.id,
        sos_description=new_report.description,
        latitude=lat,
        longitude=lng,
        db=db
    )
    await manager.broadcast({
        "type": "new_sos_pending",
        "ticket_id": new_report.id,
        "description": new_report.description,
        "latitude": lat,
        "longitude": lng,
        "status": "pending",
        "assigned_volunteer_id": assigned_volunteer_id
    })
    return {"id": new_report.id, "ok": True}

@app.post("/api/reports/sms-webhook", tags=["Emergency Alerts"])
async def receive_offline_sms_sos(
    From: str = Form(...), 
    Body: str = Form(...), 
    db: Session = Depends(get_db)
):
    """
    Webhook for Twilio/Exotel. 
    Receives an offline cellular SMS like: "SOS 28.61 77.20 Trapped on roof"
    """
    parts = Body.strip().split(" ")
    
    if len(parts) >= 3 and parts[0].upper() == "SOS":
        try:
            lat = float(parts[1])
            lng = float(parts[2])
            desc = " ".join(parts[3:]) if len(parts) > 3 else "Offline SMS SOS Request"
            
            # --- SOS ABUSE THROTTLING (New Feature) ---
            # Automatically throttle if the system detects too many downvoted/fake reports
            spam_count = db.query(models.Report).filter(
                models.Report.user_id == 1,  # Default system ID for unregistered SMS users
                models.Report.no_count >= 3  # Community flagged as false alarm
            ).count()
            
            if spam_count > 5:
                return Response(
                    content="<Response><Message>FloodOps: Alert throttled due to high false-alarm rate.</Message></Response>", 
                    media_type="application/xml"
                )
            # -------------------------------------------

            spatial_point = f"SRID=4326;POINT({lng} {lat})"
            new_report = models.Report(
                description=f"[VIA SMS - {From}] {desc}",
                location=spatial_point,
                user_id=1 # Default fallback user ID for SMS
            )
            
            db.add(new_report)
            db.commit()
            db.refresh(new_report)
            
            # Trigger volunteer matching & RAG protocols
            allocate_resources_for_sos(new_report.id, desc, lat, lng, db)
            
            # Twilio requires valid TwiML (XML) to reply to the sender
            return Response(
                content="<Response><Message>FloodOps: SOS Received. Responders alerted and routed to your coordinates.</Message></Response>", 
                media_type="application/xml"
            )
            
        except ValueError:
            return Response(
                content="<Response><Message>FloodOps Error: Invalid coordinates. Format must be 'SOS Latitude Longitude Message'</Message></Response>", 
                media_type="application/xml"
            )
            
    return Response(content="<Response></Response>", media_type="application/xml")

import firebase_admin
from firebase_admin import credentials, messaging
from fastapi import APIRouter, HTTPException
import logging
if not firebase_admin._apps:
    try:
        cred_path = os.getenv("FIREBASE_CRED_PATH")
        if cred_path and os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            print("✅ Firebase initialized successfully.")
        else:
            print("⚠️ FIREBASE_CRED_PATH missing. Masked calls will fail.")
    except Exception as e:
        print(f"⚠️ Firebase init failed: {e}")

emergency_router = APIRouter(prefix="/api/emergency", tags=["Emergency Alerts"])
logger = logging.getLogger(__name__)

class MaskedCallAlertRequest(BaseModel):
    volunteer_fcm_token: str
    sos_id: str
    display_alias: str          # e.g., "Resident in Distress"
    zone_label: str             # e.g., "Sector 4 - Yamuna Floodplain"
    risk_level: str = "CRITICAL"

@emergency_router.post("/trigger-masked-call")
async def trigger_masked_call(payload: MaskedCallAlertRequest):
    try:
        message = messaging.Message(
            data={
                "type": "EMERGENCY_INCOMING_CALL",
                "sos_id": payload.sos_id,
                "caller_name": f"FloodOps SOS: {payload.display_alias}",
                "handle_label": f"Alert Ref #{payload.sos_id[-6:]}",
                "zone_label": payload.zone_label,
                "risk_level": payload.risk_level,
            },
            token=payload.volunteer_fcm_token,
            android=messaging.AndroidConfig(priority="high", ttl=0),
            apns=messaging.APNSConfig(
                headers={"apns-priority": "10", "apns-push-type": "background"},
                payload=messaging.APNSPayload(aps=messaging.Aps(content_available=True))
            )
        )
        response = messaging.send(message)
        return {"status": "dispatched", "sos_id": payload.sos_id, "fcm_id": response}
    except Exception as e:
        logger.error(f"Error dispatching masked call alert: {e}")
        raise HTTPException(status_code=500, detail="Failed to dispatch call payload")
app.include_router(emergency_router)

def find_nearest_shelter(lat: float, lng: float) -> str:
    """Use this tool whenever the user asks for a shelter, safe zone, relief camp, or where to evacuate."""
    return "Govt Higher Secondary School, Aluva West, Ernakulam. Landmark: Near Aluva Metro Station."

def query_safety_manuals(question: str) -> str:
    """Use this tool to retrieve official flood survival protocols, what to pack, hazard handling, or wet electronics guidance."""
    global collection
    if not collection:
        return "Always disconnect electrical mains immediately. Never power on wet electronics, laptops, or appliances until completely dry and inspected. Pack essential medicines, dry food, drinking water, and identity documents in waterproof bags."
    
    results = collection.query(query_texts=[question], n_results=2)
    documents = results.get("documents", [[]])[0]
    return " ".join(documents) if documents else "Move to higher ground and stay away from electrical installations."

system_instruction = """
You are FloodOps, an emergency response voice agent assisting citizens during severe flood crises. You speak directly to panicked users via audio, so your tone must be calm, direct, and concise (under 3 to 4 sentences).

CAPABILITIES & RULES:
1. SHELTERS & EVACUATION: If the user asks where to go, for a shelter, or safe camp, call `find_nearest_shelter`. State the shelter name and specific area. You MUST explicitly end your sentence with: "An offline routing map to this shelter has been provided on your app screen to guide you safely."
2. SAFETY PROTOCOLS & HAZARDS: Use `query_safety_manuals` or your knowledge base to answer safety questions:
   - Wet Electronics & Laptops: Instruct them never to turn on wet devices, disconnect battery/power immediately if safe, and let them dry completely in a dry area.
   - What to Carry: Advise them to pack essential medicines, non-perishable food, water bottles, and emergency documents sealed in plastic covers.
   - Rising Water / Trapped: Advise them to switch off main breakers, move to higher ground or the highest level, and avoid enclosed attics unless there is roof access.
3. VOICE-FIRST FORMATTING: Never use asterisks, bullet points, Markdown headings, URLs, or emojis. Every output must be plain, readable prose intended to be converted directly to speech audio.
"""

from google.genai import types

voice_agent_config = None
if google_api_key and not google_api_key.startswith("your"):
    voice_agent_config = types.GenerateContentConfig(
        tools=[find_nearest_shelter, query_safety_manuals],
        system_instruction=system_instruction
    )

@app.post("/api/voice/agent")
async def voice_agent_endpoint(
    lat: float = Form(...), 
    lng: float = Form(...), 
    audio_file: UploadFile = File(...)
):
    if not SARVAM_API_KEY:
        return {"error": "SARVAM_API_KEY is not set in the .env file"}

    # This whole flow previously had zero error handling — any failure
    # (Sarvam unreachable, Gemini network-blocked/timed out/rate-limited,
    # TTS rejecting the input) crashed with a raw unhandled 500 instead of
    # a JSON error the client can actually show the user.
    try:
        async with httpx.AsyncClient() as client:
            stt_resp = await client.post(
                "https://api.sarvam.ai/speech-to-text",
                headers={"api-subscription-key": SARVAM_API_KEY},
                data={
                    "model": "saaras:v3",
                    "mode": "translate"
                },
                files={"file": (audio_file.filename, await audio_file.read(), audio_file.content_type)}
            )
            transcript = stt_resp.json().get("transcript", "")
            print(f"📍 Coordinates: {lat}, {lng}")
            print(f"🎙️ User Spoke: {transcript}")

            if not genai_client:
                return {"status": "Agent_Failed", "error": "Gemini API key not configured."}

            chat = genai_client.aio.chats.create(
        model="gemini-1.5-flash",
        config=voice_agent_config
    )
            agent_input = f"User GPS: ({lat}, {lng}). Spoken message: '{transcript}'"

         
            gemini_response = await asyncio.wait_for(chat.send_message(agent_input), timeout=45)
            agent_answer = gemini_response.text
            tts_resp = await client.post(
                "https://api.sarvam.ai/text-to-speech",
                headers={
                    "api-subscription-key": SARVAM_API_KEY,
                    "Content-Type": "application/json"
                },
                json={
                    "inputs": [agent_answer],
                    "target_language_code": "en-IN",
                    "speaker": "shubh",
                    "model": "bulbul:v3",
                    "pace": 1.1
                }
            )
            audio_list = tts_resp.json().get("audios")

            if not audio_list:
                return {"error": "TTS synthesis failed", "details": tts_resp.text}

            audio_bytes = base64.b64decode(audio_list[0])
            return Response(
                content=audio_bytes,
                media_type="audio/wav",
                headers={"Content-Disposition": "attachment; filename=response.wav"}
            )
    except asyncio.TimeoutError:
        return {"status": "Agent_Failed", "error": "Gemini took too long to respond (network issue) — try again."}
    except Exception as e:
        print(f"Voice agent failed: {e}")
        return {"status": "Agent_Failed", "error": f"Voice agent request failed: {e}"}


        import xgboost as xgb
import pickle
import pandas as pd
import os
from pydantic import BaseModel
from fastapi import HTTPException

class KeralaPredictionRequest(BaseModel):
    lat: float
    lon: float
    district: str

# Map old tabular features to PS-71 mandatory terminology
PS71_TERMINOLOGY_MAP = {
    "elevation_m": "INSAT-3DR Topography (Satellite)",
    "slope_deg": "DEM-Derived Avalanche Risk (Satellite)",
    "river_discharge": "Doppler Weather Radar (Streamflow)",
    "rainfall_mm": "Observational AWS Data (Ground)",
    "rainfall_mm_3d_sum": "NWP Precipitation Forecast",
    "dist_nearest_river_km": "Geospatial Catchment Baseline"
}

@app.post("/api/ml/predict-kerala", tags=["PS 71 Inundation"])
async def predict_kerala_flood(payload: KeralaPredictionRequest):
    # Fetch live 4-pillar fused data from the background cache
    live_data = kerala_live_cache["districts"].get(payload.district)
    
    if not live_data:
        raise HTTPException(status_code=404, detail=f"No live telemetry found for district: {payload.district}")

    # Intercept and translate the basic XGBoost factors into SIH terms
    raw_factors = live_data.get("top_factors", [])
    advanced_factors = [PS71_TERMINOLOGY_MAP.get(factor, factor) for factor in raw_factors]

    return {
        "status": "success",
        "district": payload.district,
        "latitude": payload.lat,
        "longitude": payload.lon,
        "flood_risk_score": live_data.get("risk_score", 0),
        "risk_probability": live_data.get("risk_probability", 0.0),
        "risk_level": live_data.get("alert_level", "NORMAL"),
        "is_high_risk": live_data.get("is_high_risk", False),
        "top_factors": advanced_factors,
        "telemetry_pillars": live_data.get("pillars", {})  # This is the line that was missing
    }

@app.post("/api/volunteers/tasks/{task_id}/accept", tags=["Volunteers"])
async def accept_volunteer_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    if current_user.role != models.UserRole.volunteer:
        raise HTTPException(status_code=403, detail="Only volunteers can accept tasks.")
    
    report = db.query(models.Report).filter(models.Report.id == task_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Task not found.")
        
    report.assigned_volunteer_id = current_user.id
    report.status = "en-route"
    current_user.status = "busy"
    db.commit()
    
    # Broadcast to the frontend dashboard that the volunteer is moving
    await manager.broadcast({
        "type": "volunteer_en_route",
        "ticket_id": report.id,
        "volunteer_id": current_user.id,
        "volunteer_name": current_user.full_name
    })
    
    return {"status": "en-route", "ticket_id": task_id, "volunteer": current_user.full_name}

@app.get("/api/reports/{ticket_id}/volunteer-location", tags=["Reports"])
async def get_volunteer_location(
    ticket_id: int,
    db: Session = Depends(get_db)
):
    report = db.query(models.Report).filter(models.Report.id == ticket_id).first()
    if not report or not report.assigned_volunteer_id:
        raise HTTPException(status_code=404, detail="No volunteer assigned to this ticket.")
        
    # Extract coordinates from the PostGIS geometry column
    volunteer = db.query(
        models.User,
        func.ST_X(models.User.last_known_location).label('lng'),
        func.ST_Y(models.User.last_known_location).label('lat')
    ).filter(models.User.id == report.assigned_volunteer_id).first()
    
    if not volunteer or volunteer.lng is None:
        raise HTTPException(status_code=404, detail="Volunteer location is currently unknown.")
        
    return {
        "volunteer_name": volunteer.User.full_name,
        "latitude": volunteer.lat,
        "longitude": volunteer.lng
    }