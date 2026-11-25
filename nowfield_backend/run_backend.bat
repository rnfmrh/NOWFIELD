@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ===================================================
echo   NOWFIELD Backend Server (Local SQLite DB Mode)
echo   DB File : %~dp0nowfield.db
echo   Port    : 8000 (http://127.0.0.1:8000)
echo ===================================================

set DATABASE_URL=sqlite:///./nowfield.db

if exist "venv\Scripts\python.exe" (
    echo [1/2] Using virtual environment (venv)...
    "venv\Scripts\python.exe" -m pip install -q -r requirements.txt
    echo [2/2] Starting FastAPI server on port 8000...
    "venv\Scripts\python.exe" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
) else (
    echo [1/2] Checking required Python packages...
    python -m pip install -q -r requirements.txt
    echo [2/2] Starting FastAPI server on port 8000...
    python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
)

pause
