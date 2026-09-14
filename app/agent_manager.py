import os
import uuid
import json
import datetime
import chromadb
from google import genai
from sqlalchemy.orm import Session
from .models import AgentRunLog, AlertRecord

# Standardize on a single API key to prevent silent LLM failures
api_key = os.environ.get("GOOGLE_API_KEY")
genai_client = None
if api_key:
    # Initialize the new SDK Client instead of the old GenerativeModel
    genai_client = genai.Client(api_key=api_key)

# Initialize offline ChromaDB for NDMA RAG integration
try:
    chroma_client = chromadb.PersistentClient(path="./chroma_db")
    collection = chroma_client.get_collection(name="survival_manuals")
except Exception:
    collection = None

def run_floodops_agents(db: Session, district: str, incident_data: str):
    run_id = str(uuid.uuid4())
    execution_chain = []
    
    try:
        # Agent 1: Risk Analyst
        prompt_1 = f"Analyze flood data for {district}: {incident_data}. Output a strict threat level assessment in 2 sentences."
        response_1 = genai_client.models.generate_content(
            model='gemini-3.5-flash',
            contents=prompt_1
        ).text
        execution_chain.append({"agent": "Risk Analyst", "output": response_1})
        
        # --- RAG Protocol Trigger ---
        ndma_context = "Standard evacuation protocols apply."
        if collection:
            results = collection.query(query_texts=[f"Evacuation and rescue deployment for {incident_data}"], n_results=2)
            if results and results['documents'] and len(results['documents'][0]) > 0:
                ndma_context = "\n".join(results['documents'][0])

        # Agent 2: Resource Allocator (Now grounded in NDMA Guidelines)
        prompt_2 = (
            f"Based on this analyst report: {response_1}, and these official NDMA guidelines: {ndma_context}, "
            f"allocate specific rescue units, boats, and generate a step-by-step tactical checklist for responders in {district}."
        )
        response_2 = genai_client.models.generate_content(
            model='gemini-3.5-flash',
            contents=prompt_2
        ).text
        execution_chain.append({"agent": "Resource Allocator", "output": response_2})
        
        # Agent 3: Communications
        prompt_3 = (
            f"Turn this allocation plan into a rapid public SMS alert: {response_2}. "
            "Respond ONLY with a valid JSON object containing exactly these keys: "
            "'alert_level' (CRITICAL, HIGH, or MODERATE), 'message' (the 1-sentence SMS), and 'helpline' (a generic 4-digit number like 1070)."
        )
        response_3 = genai_client.models.generate_content(
            model='gemini-3.5-flash',
            contents=prompt_3
        ).text
        clean_json_str = response_3.replace("```json", "").replace("```", "").strip()
        comms_data = json.loads(clean_json_str)
        execution_chain.append({"agent": "Communications", "output": comms_data})
        
        new_alert = AlertRecord(
            district=district,
            alert_level=comms_data.get("alert_level", "HIGH"),
            message=comms_data.get("message", "Emergency alert generated."),
            helpline=comms_data.get("helpline", "1070")
        )
        db.add(new_alert)
        
        # Agent 4: Coordinator
        prompt_4 = f"Summarize the operation for {district} into a 3-bullet executive summary based on the allocations."
        final_summary = genai_client.models.generate_content(
            model='gemini-3.5-flash',
            contents=prompt_4
        ).text
        execution_chain.append({"agent": "Coordinator", "output": final_summary})
        
        # Save Success Log
        new_log = AgentRunLog(
            run_id=run_id,
            district=district,
            status="SUCCESS",
            coordinator_summary=final_summary,
            execution_chain=execution_chain,
            created_at=datetime.datetime.utcnow()
        )
        db.add(new_log)
        db.commit()
        db.refresh(new_log)
        
        return new_log

    except Exception as e:
        db.rollback()
        error_log = AgentRunLog(
            run_id=run_id,
            district=district,
            status="FAILED",
            coordinator_summary=f"Agent chain failed: {str(e)}",
            execution_chain=execution_chain,
            created_at=datetime.datetime.utcnow()
        )
        db.add(error_log)
        db.commit()
        raise e