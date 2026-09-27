"""
inundation_depth_proxy.py

Reusable module for the inundation depth-proxy formula. Explicitly an
ESTIMATE, not a physical/hydrodynamic simulation -- see project README for
why full flood-physics modeling (HAND, drainage-network analysis) is out
of scope for the current timeline, and this proxy is the honest middle
ground: real terrain + real predicted severity, combined through a simple,
transparent, stated formula rather than invented numbers.

Formula:
    estimated_depth_cm = base_depth[risk_category] * terrain_factor
    terrain_factor = clamp(1.5 - (elevation_m / 500) - (slope_deg / 30), 0.3, 1.8)

Lower elevation + flatter slope -> water pools more -> higher terrain_factor.
Higher elevation + steeper slope -> drains faster -> lower terrain_factor.
"""

BASE_DEPTH_CM = {"No Rain": 0, "Light": 5, "Moderate": 20, "Severe": 60}


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def terrain_factor(elevation_m: float, slope_deg: float) -> float:
    return clamp(1.5 - (elevation_m / 500) - (slope_deg / 30), 0.3, 1.8)


def estimated_depth_cm(risk_category: str, elevation_m: float, slope_deg: float) -> float:
    if risk_category not in BASE_DEPTH_CM:
        raise ValueError(f"Unknown risk_category: {risk_category!r}. Expected one of {list(BASE_DEPTH_CM)}.")
    base = BASE_DEPTH_CM[risk_category]
    factor = terrain_factor(elevation_m, slope_deg)
    return round(base * factor, 1)


if __name__ == "__main__":
    # Quick sanity check, matching the real terrain contrast we've seen in
    # this project: Idukki/Wayanad (high elevation) should show much lower
    # estimated depth than low-lying districts, at the same severity.
    print("Sanity check -- same 'Severe' risk, different terrain:")
    print("  Idukki   (elev=841m, slope=1.96):", estimated_depth_cm("Severe", 841.0, 1.962), "cm")
    print("  Kasaragod (elev=3m,  slope=0.23):", estimated_depth_cm("Severe", 3.0, 0.232), "cm")
