import os
from datetime import datetime, timedelta
from typing import Optional, List
from jose import JWTError, jwt
import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from .database import get_db
from . import models

# --- Secret & Algorithm Configuration ---
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "floodops_super_secret_hackathon_key_2026")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 1440  # 24 Hours

# --- PS 26071 Role Constants ---
ROLE_PREDICTOR = "PREDICTOR"   # IMD Meteorologists & MoES Scientists
ROLE_RESPONDER = "RESPONDER"   # District Magistrates, NDMA, NDRF
ROLE_CITIZEN = "CITIZEN"       # General Public & Field Volunteers

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/v1/auth/login")
oauth2_scheme_optional = OAuth2PasswordBearer(tokenUrl="api/v1/auth/login", auto_error=False)


def hash_password(password: str) -> str:
    pwd_bytes = password.encode('utf-8')[:72]
    hashed = bcrypt.hashpw(pwd_bytes, bcrypt.gensalt())
    return hashed.decode('utf-8')


def verify_password(plain_password: str, hashed_password: str) -> bool:
    pwd_bytes = plain_password.encode('utf-8')[:72]
    return bcrypt.checkpw(pwd_bytes, hashed_password.encode('utf-8'))


def create_access_token(data: dict) -> str:
    """Encodes user identity, email, and explicit PS 26071 role into the JWT payload."""
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def _normalize_role(role_val: Any) -> str:
    """Helper to convert Enum or string role into standardized uppercase format."""
    if role_val is None:
        return ROLE_CITIZEN
    val = role_val.value if hasattr(role_val, 'value') else str(role_val)
    val_upper = val.strip().upper()
    
    # Map old FloodOps roles to the new 3-tier hierarchy
    if val_upper in ["OFFICIAL", "ADMIN", "PREDICTOR"]:
        return ROLE_PREDICTOR
    elif val_upper in ["VOLUNTEER", "RESPONDER"]:
        return ROLE_RESPONDER
    return ROLE_CITIZEN


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> models.User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: Optional[str] = payload.get("sub")
        if email is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
        
    user = db.query(models.User).filter(models.User.email == email).first()
    if user is None:
        raise credentials_exception
    return user


def get_current_user_optional(
    token: Optional[str] = Depends(oauth2_scheme_optional),
    db: Session = Depends(get_db),
) -> Optional[models.User]:
    """Allows guest access while recognizing signed-in accounts if a token is present."""
    if token is None:
        return None
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: Optional[str] = payload.get("sub")
        if email is None:
            return None
    except JWTError:
        return None
    return db.query(models.User).filter(models.User.email == email).first()


# --- Role-Based Access Control (RBAC) Dependencies ---

def require_predictor(current_user: models.User = Depends(get_current_user)):
    """Gate for IMD Meteorologists & MoES Data Analysts."""
    user_role = _normalize_role(getattr(current_user, "role", None))
    if user_role != ROLE_PREDICTOR:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted: IMD Meteorologists and MoES Officials only."
        )
    return current_user


def require_responder(current_user: models.User = Depends(get_current_user)):
    """Gate for Disaster Management, District Magistrates, and NDRF."""
    user_role = _normalize_role(getattr(current_user, "role", None))
    if user_role not in [ROLE_RESPONDER, ROLE_PREDICTOR]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted: Disaster Responders and Emergency Officials only."
        )
    return current_user


# Legacy aliases preserved for backward compatibility
def require_official(current_user: models.User = Depends(get_current_user)):
    return require_responder(current_user)


def require_volunteer(current_user: models.User = Depends(get_current_user)):
    return current_user