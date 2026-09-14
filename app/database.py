import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from dotenv import load_dotenv

load_dotenv()

SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")

# Enforce PostgreSQL + PostGIS requirement
if not SQLALCHEMY_DATABASE_URL or not SQLALCHEMY_DATABASE_URL.startswith("postgresql"):
    raise ValueError(
        "CRITICAL ERROR: DATABASE_URL is missing or invalid. "
        "PrecipOps requires a PostgreSQL connection string with the PostGIS extension enabled."
    )

engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()