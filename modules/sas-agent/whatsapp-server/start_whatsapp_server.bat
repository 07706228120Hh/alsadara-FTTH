@echo off
REM ============================================================
REM  Aluklaa WhatsApp local server launcher (ASCII only).
REM  Installs deps on first run, then starts the server.
REM ============================================================
setlocal
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Node.js is not installed or not in PATH.
  echo Install Node.js LTS from https://nodejs.org then run this again.
  pause
  exit /b 1
)

if not exist "node_modules" (
  echo [setup] Installing dependencies (first run, may take a few minutes)...
  call npm install
  if errorlevel 1 (
    echo [ERROR] npm install failed.
    pause
    exit /b 1
  )
)

echo [start] Starting WhatsApp server on http://127.0.0.1:3100 ...
node server.js
pause
