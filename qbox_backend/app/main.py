"""QBOX backend entry point.

Run (from the qbox_backend folder):
    .venv\\Scripts\\python -m uvicorn app.main:app --reload --port 8080

API docs with "Try it out" buttons: http://localhost:8080/docs
(switched off when QBOX_APP_ENV=production, so outsiders cannot browse the API)
"""

import logging

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.auth.router import router as auth_router
from app.calendar.router import router as calendar_router
from app.config import get_settings
from app.database import engine
from app.errors import register_error_handlers
from app.users.router import router as users_router

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("qbox")

_docs = not get_settings().is_production

app = FastAPI(
    title="QBOX API",
    description="Accounts, login and business data for the QBOX app.",
    version="0.3.0",
    docs_url="/docs" if _docs else None,
    redoc_url="/redoc" if _docs else None,
    openapi_url="/openapi.json" if _docs else None,
)
register_error_handlers(app)
app.include_router(auth_router)
app.include_router(users_router)
app.include_router(calendar_router)


@app.get("/health", tags=["Health"], summary="Is the server (and database) up?")
def health():
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except SQLAlchemyError:
        log.warning("Health check: database is not reachable")
        return JSONResponse(status_code=503, content={"status": "DOWN"})
    return {"status": "UP"}
