# KIKO Personal AI Agent Platform

A secure, modular, 3-tier personal AI assistant system for controlling Windows laptops from mobile phones through natural-language text and voice commands.

```text
                ┌─────────────────────┐
                │   Flutter Mobile    │
                │       App           │
                │ Chat + Voice + UI   │
                └──────────┬──────────┘
                           │
                    HTTPS / WebSocket
                           │
                           ▼
                ┌─────────────────────┐
                │    FastAPI Server   │
                │                     │
                │ AI Agent            │
                │ Orchestrator        │
                │ Tool Registry       │
                │ Memory / RAG        │
                │ Authentication      │
                └──────────┬──────────┘
                           │
                    WebSocket / HTTPS
                           │
                           ▼
                ┌─────────────────────┐
                │ Windows Background  │
                │       Agent         │
                │                     │
                │ Files               │
                │ Applications        │
                │ Browser             │
                │ Keyboard / Mouse    │
                │ System              │
                └─────────────────────┘
```

---

## System Architecture

1. **Flutter Mobile Application (`mobile/`)**: The primary user interface for natural language text chat, voice assistant, task execution progress, action approvals, device pairing, memory, and system settings.
2. **FastAPI AI Backend (`backend/`)**: Central AI Brain handling JWT authentication, WebSocket connection hub, AI provider abstraction (OpenAI, Ollama, Local LLM), Tool Registry, Permission Engine, RAG, and Task Orchestrator.
3. **Windows Background Agent (`windows-agent/`)**: Lightweight, silent Python daemon/service running on your Windows laptop. Receives approved commands from FastAPI over WebSocket and executes file, application, browser, media, keyboard/mouse, and system operations without any visible GUI window.

---

## Quickstart & Setup Instructions

### 1. Start the FastAPI Backend Server

```bash
cd backend
python -m venv venv
# On Windows PowerShell:
.\venv\Scripts\Activate.ps1

pip install -r requirements.txt
python app/main.py
```
FastAPI server starts at `http://localhost:8000`. API documentation at `http://localhost:8000/docs`.

---

### 2. Start the Windows Silent Background Agent Daemon

Run locally on your Windows laptop:

```bash
cd windows-agent
pip install -r requirements.txt

python agent.py
```
The agent connects silently to `ws://localhost:8000/ws/agent/windows_laptop_daemon_1`.

---

### 3. Run the Flutter Mobile Application

```bash
cd mobile
flutter pub get
flutter run
```
Launch on your Android/iOS mobile phone or emulator.

---

## Testing Commands (Phase 1 Target Flows)

Send these commands from your Flutter Mobile App:

1. `"Create a folder named AI Projects inside Documents"`
2. `"Open Chrome"`
3. `"Search YouTube for Iron Man"`
4. `"Find my resume"`
5. `"Open Notepad and type Hello"`
6. `"Take a screenshot"`
7. `"Apply for suitable AI jobs"` (Triggers High-Risk Mobile Approval request!)

---

## API Summary

- `GET /` - System health & AI provider status
- `POST /api/v1/tasks` - Create natural language task execution
- `GET /api/v1/tasks` - List active tasks and step history
- `GET /api/v1/approvals` - List pending high-risk approval requests
- `POST /api/v1/approvals/{id}/resolve` - Approve or reject pending action
- `GET /api/v1/devices` - List connected devices & statuses
- `WS /ws/client/{client_id}` - Real-time mobile client event socket
- `WS /ws/agent/{device_id}` - Real-time Windows Agent command socket
