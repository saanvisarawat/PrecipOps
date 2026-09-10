from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import List

router = APIRouter(prefix="/routing", tags=["Evacuation Routing (USP 1)"])

# --- Schemas ---
class BoundingBox(BaseModel):
    min_lat: float
    max_lat: float
    min_lon: float
    max_lon: float
    description: str

class BlockedNodesResponse(BaseModel):
    zone_id: str
    blocked_bounding_boxes: List[BoundingBox]
    action: str

# --- Endpoint ---
@router.get("/blocked-nodes", response_model=BlockedNodesResponse)
async def get_blocked_nodes(
    zone_id: str = Query(..., description="The ID of the inundated zone (e.g., INUND-SEC-MUM-01)")
):
    """
    Translates an inundation polygon into specific rectangular bounding boxes 
    representing impassable street segments for the Dijkstra routing engine.
    """
    
    # 1. Parse the city code from the zone_id (e.g., "MUM" from "INUND-SEC-MUM-01")
    zone_upper = zone_id.upper()
    
    # 2. Hardcoded impassable street bounding boxes for the hackathon demo
    if "MUM" in zone_upper:
        boxes = [
            BoundingBox(
                min_lat=19.013, max_lat=19.022, 
                min_lon=72.835, max_lon=72.845, 
                description="Hindmata Junction - Completely Submerged"
            ),
            BoundingBox(
                min_lat=19.024, max_lat=19.030, 
                min_lon=72.838, max_lon=72.848, 
                description="Milan Subway - Impassable"
            )
        ]
    elif "DEL" in zone_upper:
        boxes = [
            BoundingBox(
                min_lat=28.625, max_lat=28.635, 
                min_lon=77.235, max_lon=77.245, 
                description="ITO Ring Road Underpass - Waterlogged"
            )
        ]
    else:
        # Fallback for Ernakulam / Any other city
        boxes = [
            BoundingBox(
                min_lat=9.970, max_lat=9.980, 
                min_lon=76.280, max_lon=76.290, 
                description="MG Road Metro Axis - Impassable"
            )
        ]

    return BlockedNodesResponse(
        zone_id=zone_id,
        blocked_bounding_boxes=boxes,
        action="Set graph node weights inside these bounding boxes to infinity."
    )