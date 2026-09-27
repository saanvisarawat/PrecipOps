import os
import json
import math
import datetime
import pandas as pd
import xgboost as xgb

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(CURRENT_DIR, "flood_risk_model.json")
COLUMNS_PATH = os.path.join(CURRENT_DIR, "model_columns.json")

# Load model on startup
booster = xgb.Booster()
booster.load_model(MODEL_PATH)

# Load expected columns and metadata from model_columns.json
with open(COLUMNS_PATH, "r") as f:
    config = json.load(f)

EXPECTED_COLUMNS = config["features"]
CLASSES = config.get("classes", ["No Rain", "Light", "Moderate", "Severe"])
SEVERE_THRESHOLD = config.get("severe_threshold", 0.20)

def predict_district_risk(feature_dict: dict) -> dict:
    """
    Takes district telemetry, automatically synthesizes 4-pillar consensus
    and rolling features required by the trained XGBoost model, and returns
    risk probabilities along with the estimated flood depth.
    """
    data = feature_dict.copy()

    rain = float(data.get("om_rainfall_mm", 0.0))
    rain_15d = float(data.get("om_rainfall_mm_15d_sum", rain * 4.0))
    discharge = float(data.get("om_river_discharge", 0.0))
    discharge_15d = float(data.get("om_river_discharge_15d_sum", discharge * 4.0))

    # 1. Synthesize rolling sums if omitted
    data.setdefault("om_rainfall_mm_3d_sum", max(rain, rain_15d * 0.25))
    data.setdefault("om_rainfall_mm_7d_sum", max(rain, rain_15d * 0.55))
    data.setdefault("om_river_discharge_3d_sum", max(discharge, discharge_15d * 0.25))
    data.setdefault("om_river_discharge_7d_sum", max(discharge, discharge_15d * 0.55))

    # 2. Synthesize complementary pillar estimates from rainfall
    data.setdefault("aws_rainfall_mm", rain)
    data.setdefault("aws_observed", 1.0 if rain > 0 else 0.0)
    data.setdefault("sat_precipitation_mm", rain)
    data.setdefault("sat_observed", 1.0 if rain > 0 else 0.0)
    data.setdefault("nwp_precipitation_sum", rain_15d * 0.15)
    data.setdefault("nwp_observed", 1.0)
    data.setdefault("nwp_temperature_2m_max", 30.5)
    data.setdefault("nwp_temperature_2m_min", 24.0)
    data.setdefault("nwp_wind_speed_10m_max", 15.0)
    data.setdefault("nwp_relative_humidity_2m_mean", 85.0 if rain > 10 else 65.0)

    # 3. Derive 4-Pillar consensus features
    data.setdefault("consensus_rainfall_mm", rain)
    data.setdefault("consensus_rainfall_sources", 3.0 if rain > 0 else 1.0)

    # 4. Seasonal temporal encodings
    now = datetime.datetime.now()
    day_of_year = now.timetuple().tm_yday
    data.setdefault("season_sin", math.sin(2 * math.pi * day_of_year / 365.25))
    data.setdefault("season_cos", math.cos(2 * math.pi * day_of_year / 365.25))
    # Kerala monsoons typically span June-September (approx DOY 152 to 273)
    data.setdefault("is_monsoon_season", 1.0 if 150 <= day_of_year <= 280 or rain > 50 else 0.0)

    # 5. Radar features (handled safely)
    data.setdefault("rad_dbz", 0.0)
    data.setdefault("rad_rainfall_rate_mm_hr", 0.0)

    # 6. Fill any remaining columns
    for col in EXPECTED_COLUMNS:
        data.setdefault(col, 0.0)

    df = pd.DataFrame([data])
    df_ordered = df[EXPECTED_COLUMNS]

    # Run XGBoost inference
    dmatrix = xgb.DMatrix(df_ordered)
    probabilities = booster.predict(dmatrix)[0]

    prob_map = {label: float(prob) for label, prob in zip(CLASSES, probabilities)}
    severe_prob = prob_map.get("Severe", 0.0)

    # Classification logic
    if severe_prob >= SEVERE_THRESHOLD:
        category = "Severe"
    else:
        argmax_idx = int(probabilities.argmax())
        category = CLASSES[argmax_idx]

    # Baseline depth calculation (cm)
    # Baseline depth calculation (cm)
    base_depths = {
        "No Rain": 0.0,
        "Light": 5.0,
        "Moderate": 25.0,  # Base 25cm (approx 10 inches)
        "Severe": 75.0     # Base 75cm (approx 2.5 feet)
    }
    
    elevation = float(data.get("srtm_elevation_m", 50.0))
    slope = float(data.get("srtm_slope_deg", 0.5))

    # Calculate terrain multiplier but CAP it between 0.5x and 2.5x
    raw_multiplier = (50.0 / (elevation + 10.0)) * (1.0 / (slope + 0.5))
    terrain_multiplier = min(2.5, max(0.5, raw_multiplier))
    
    estimated_depth_cm = round(base_depths[category] * terrain_multiplier * (1.0 + severe_prob), 1)

    return {
        "risk_category": category,
        "severe_probability": round(severe_prob, 4),
        "all_probabilities": {k: round(v, 4) for k, v in prob_map.items()},
        "estimated_depth_cm": estimated_depth_cm
    }