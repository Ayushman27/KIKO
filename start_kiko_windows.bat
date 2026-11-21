@echo off
title Starting KIKO AI Agent System
echo ============================================================
echo   Starting KIKO Personal AI Agent Platform (Windows)
echo ============================================================

echo [1/3] Launching FastAPI Backend Server...
start "KIKO - Backend Server" cmd /k "cd /d %~dp0backend && .\venv\Scripts\activate && python app\main.py"

echo Waiting for backend to initialize...
timeout /t 3 /nobreak >nul

echo [2/3] Launching Windows Background Agent...
start "KIKO - Windows Agent" cmd /k "cd /d %~dp0windows-agent && python agent.py"

echo Waiting for agent to connect...
timeout /t 2 /nobreak >nul

echo [3/3] Launching Windows Desktop Application...
start "" "%~dp0mobile\build\windows\x64\runner\Release\jarvis_mobile.exe"

echo.
echo ============================================================
echo   KIKO Windows Stack is Running!
echo   - Backend: http://localhost:8000
echo   - Windows Agent: Connected to ws://localhost:8000/ws/agent/...
echo   - Desktop App: Running
echo ============================================================
