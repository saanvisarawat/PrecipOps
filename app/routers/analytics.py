from fastapi import APIRouter, Query
from pydantic import BaseModel
from typing import List

router = APIRouter(prefix="/analytics", tags=["Comparative Storm Telemetry (USP 3)"])

class HistoricalBenchmark(BaseModel):
    event_name: str
    year: int
    peak_rainfall_mm_hr: float
    max_radar_dbz: float
    hourly_trend: List[float]

class StormComparisonResponse(BaseModel):
    district: str
    current_storm_name: str
    current_peak_rainfall_mm_hr: float
    current_max_radar_dbz: float
    current_hourly_trend: List[float]
    historical_benchmarks: List[HistoricalBenchmark]

@router.get("/storm-comparison", response_model=StormComparisonResponse)
async def get_storm_comparison(
    district: str = Query("Mumbai", description="Target metropolitan district")
):
    """
    Provides comparative time-series telemetry contrasting the active storm 
    against major historical flood benchmarks for IMD Predictor analytics.
    """
    # Active simulation hourly rainfall trend (mm/hr) matching our simulation engine
    current_trend = [15.0, 32.5, 52.0, 72.0, 48.0, 22.0]
    
    benchmarks = [
        HistoricalBenchmark(
            event_name="Mumbai Historic Cloudburst",
            year=2005,
            peak_rainfall_mm_hr=94.0,
            max_radar_dbz=58.5,
            hourly_trend=[20.0, 45.0, 85.0, 94.0, 60.0, 30.0]
        ),
        HistoricalBenchmark(
            event_name="Chennai Urban Flood Event",
            year=2015,
            peak_rainfall_mm_hr=82.0,
            max_radar_dbz=52.0,
            hourly_trend=[10.0, 25.0, 65.0, 82.0, 55.0, 20.0]
        )
    ]

    return StormComparisonResponse(
        district=district,
        current_storm_name="Active Convective Cell (PS-71 Fused Stream)",
        current_peak_rainfall_mm_hr=72.0,
        current_max_radar_dbz=54.2,
        current_hourly_trend=current_trend,
        historical_benchmarks=benchmarks
    )