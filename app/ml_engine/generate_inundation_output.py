"""
generate_inundation_output.py

Connects the REAL trained flood_risk_model.json to the inundation depth
proxy. This runs the actual model's prediction for the latest available
day per district (not a hardcoded historical date) and produces:
  - inundation_output.json  (data, for the dashboard / any consumer)
  - inundation_output.geojson  (spatial, if kerala_districts.geojson is
    present -- see fetch_district_boundaries.py; falls back to plain
    centroid points if not)

This is the genuine "connect it to a prediction model" version --
everything downstream of the model's own predict_proba() output, using
the SAME leak-free next-day framing and the SAME 0.20 Severe threshold as
train_baseline_model.py, loaded from model_columns.json so the two never
drift out of sync with each other.

Run this where you have flood_risk_model.json, model_columns.json, and
kerala_test.csv (or your latest feature data) available:
    pip install xgboost
    python generate_inundation_output.py
"""

import json
import os
import numpy as np
import pandas as pd
import xgboost as xgb

from inundation_depth_proxy import estimated_depth_cm

# Real district centroids (used throughout this project's fetch scripts) --
# kept as a fallback so this script works even before kerala_districts.geojson
# has been fetched.
DISTRICT_CENTROIDS = {
    "Thiruvananthapuram": {"lat": 8.52, "lon": 76.93},
    "Kollam": {"lat": 8.89, "lon": 76.61},
    "Pathanamthitta": {"lat": 9.26, "lon": 76.78},
    "Alappuzha": {"lat": 9.49, "lon": 76.33},
    "Kottayam": {"lat": 9.59, "lon": 76.52},
    "Idukki": {"lat": 9.85, "lon": 76.94},
    "Ernakulam": {"lat": 9.98, "lon": 76.28},
    "Thrissur": {"lat": 10.52, "lon": 76.21},
    "Palakkad": {"lat": 10.78, "lon": 76.65},
    "Malappuram": {"lat": 11.07, "lon": 76.07},
    "Kozhikode": {"lat": 11.25, "lon": 75.78},
    "Wayanad": {"lat": 11.68, "lon": 76.13},
    "Kannur": {"lat": 11.87, "lon": 75.37},
    "Kasaragod": {"lat": 12.49, "lon": 74.98},
}

CLASS_ORDER = ["No Rain", "Light", "Moderate", "Severe"]
BOUNDARIES_PATH = "kerala_districts.geojson"  # from fetch_district_boundaries.py


def load_model_and_config():
    with open("model_columns.json") as f:
        config = json.load(f)
    booster = xgb.Booster()
    booster.load_model("flood_risk_model.json")
    return booster, config


def get_latest_feature_row_per_district(feature_cols):
    """Pull the most recent available day's features for each district from
    kerala_test.csv. In a real deployed system, this is the point where
    you'd instead pull TODAY's live om_/srtm_/sat_/aws_/nwp_ values -- the
    model/threshold logic below doesn't care where the row comes from, only
    that it has the right columns."""
    test = pd.read_csv("kerala_test.csv")
    test["date"] = pd.to_datetime(test["date"])
    latest_per_district = (
        test.sort_values("date").groupby("district").tail(1).reset_index(drop=True)
    )
    missing = [c for c in feature_cols if c not in latest_per_district.columns]
    if missing:
        raise ValueError(f"kerala_test.csv is missing expected feature columns: {missing}")
    return latest_per_district


def predict_risk_categories(booster, config, rows: pd.DataFrame):
    feature_cols = config["features"]
    threshold = config["severe_threshold"]
    severe_idx = CLASS_ORDER.index("Severe")

    dmatrix = xgb.DMatrix(rows[feature_cols])
    probs = booster.predict(dmatrix)  # shape (n_rows, n_classes)

    default_idx = probs.argmax(axis=1)
    tuned_idx = default_idx.copy()
    tuned_idx[probs[:, severe_idx] >= threshold] = severe_idx

    results = []
    for i, row in rows.iterrows():
        results.append({
            "district": row["district"],
            "as_of_date": str(row["date"].date()),
            "predicted_risk_category": CLASS_ORDER[tuned_idx[i]],
            "severe_probability": round(float(probs[i, severe_idx]), 4),
            "elevation_m": float(row["srtm_elevation_m"]),
            "slope_deg": float(row["srtm_slope_deg"]),
        })
    return results


def attach_depth_and_geometry(predictions):
    for p in predictions:
        p["estimated_depth_cm"] = estimated_depth_cm(
            p["predicted_risk_category"], p["elevation_m"], p["slope_deg"]
        )
        centroid = DISTRICT_CENTROIDS.get(p["district"])
        if centroid:
            p["lat"], p["lon"] = centroid["lat"], centroid["lon"]
    return predictions


def build_geojson(predictions, boundaries_path=BOUNDARIES_PATH):
    by_district = {p["district"]: p for p in predictions}

    if os.path.exists(boundaries_path):
        with open(boundaries_path) as f:
            boundaries = json.load(f)
        matched = 0
        for feature in boundaries["features"]:
            name = feature["properties"].get("district")
            pred = by_district.get(name)
            if pred:
                feature["properties"]["predicted_risk_category"] = pred["predicted_risk_category"]
                feature["properties"]["estimated_depth_cm"] = pred["estimated_depth_cm"]
                feature["properties"]["severe_probability"] = pred["severe_probability"]
                feature["properties"]["as_of_date"] = pred["as_of_date"]
                matched += 1
        print(f"Used real district boundary polygons -- matched {matched}/{len(predictions)} districts.")
        return boundaries
    else:
        print(f"[info] {boundaries_path} not found -- falling back to centroid points. "
              f"Run fetch_district_boundaries.py to get real polygons.")
        features = []
        for p in predictions:
            features.append({
                "type": "Feature",
                "properties": {k: v for k, v in p.items() if k not in ("lat", "lon")},
                "geometry": {"type": "Point", "coordinates": [p["lon"], p["lat"]]},
            })
        return {"type": "FeatureCollection", "features": features}


def main():
    booster, config = load_model_and_config()
    print(f"Loaded model. Feature count: {len(config['features'])}. "
          f"Sources used: {list(config['sources_used'].keys())}. "
          f"Severe threshold: {config['severe_threshold']}")

    rows = get_latest_feature_row_per_district(config["features"])
    print(f"\nPredicting for {len(rows)} districts, as of their latest available data...")

    predictions = predict_risk_categories(booster, config, rows)
    predictions = attach_depth_and_geometry(predictions)

    for p in sorted(predictions, key=lambda x: -x["estimated_depth_cm"]):
        print(f"  {p['district']:20s} {p['predicted_risk_category']:10s} "
              f"P(Severe)={p['severe_probability']:.3f}  depth~{p['estimated_depth_cm']:.1f}cm  "
              f"(as of {p['as_of_date']})")

    with open("inundation_output.json", "w") as f:
        json.dump({"generated_from": "real trained model prediction, per-district latest available data",
                    "predictions": predictions}, f, indent=2)
    print("\nSaved inundation_output.json")

    geojson = build_geojson(predictions)
    with open("inundation_output.geojson", "w") as f:
        json.dump(geojson, f)
    print("Saved inundation_output.geojson")


if __name__ == "__main__":
    main()
