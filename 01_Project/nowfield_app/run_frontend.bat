@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ===================================================
echo   NOWFIELD Web Frontend Server (Port 8080)
echo   Local URL   : http://127.0.0.1:8080
echo   DuckDNS URL : http://mydidgu.duckdns.org:8080
echo ===================================================

if exist "build\web\index.html" (
    echo Starting web server from build\web on port 8080...
    python -m http.server 8080 --directory build\web --bind 0.0.0.0
) else (
    echo Starting web server from web_dist on port 8080...
    python -m http.server 8080 --directory web_dist --bind 0.0.0.0
)

pause
