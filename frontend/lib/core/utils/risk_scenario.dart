/// Maps a live PS-71 risk level (from POST /api/ml/predict-kerala) to the
/// `scenario` parameter GET /api/v1/inundation/simulate expects. That
/// endpoint is a canned two-scenario simulator — NORMAL is always GREEN,
/// EXTREME_EVENT is always RED, regardless of district — so which one gets
/// requested has to be decided from real data, or the panel just shows
/// worst-case every time for every district.
String scenarioForRiskLevel(String riskLevel) =>
    (riskLevel == 'CRITICAL' || riskLevel == 'WARNING') ? 'EXTREME_EVENT' : 'NORMAL';
