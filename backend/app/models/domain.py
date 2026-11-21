import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, Text, Boolean, ForeignKey, Integer, JSON
from sqlalchemy.orm import relationship
from app.database.session import Base

def generate_uuid():
    return str(uuid.uuid4())

class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=generate_uuid)
    email = Column(String, unique=True, index=True, nullable=False)
    full_name = Column(String, nullable=True)
    hashed_password = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    devices = relationship("Device", back_populates="owner", cascade="all, delete-orphan")
    tasks = relationship("Task", back_populates="user", cascade="all, delete-orphan")

class Device(Base):
    __tablename__ = "devices"

    id = Column(String, primary_key=True, default=generate_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    name = Column(String, nullable=False)
    device_type = Column(String, nullable=False) # laptop, phone, browser
    auth_token = Column(String, unique=True, nullable=False)
    status = Column(String, default="OFFLINE") # ONLINE, OFFLINE, BUSY
    last_seen = Column(DateTime, default=datetime.utcnow)
    created_at = Column(DateTime, default=datetime.utcnow)

    owner = relationship("User", back_populates="devices")

class Task(Base):
    __tablename__ = "tasks"

    id = Column(String, primary_key=True, default=generate_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    session_id = Column(String, nullable=True, index=True)
    description = Column(Text, nullable=False)
    status = Column(String, default="PENDING") # PENDING, PLANNING, RUNNING, WAITING_FOR_APPROVAL, COMPLETED, FAILED, CANCELLED
    priority = Column(String, default="MEDIUM") # LOW, MEDIUM, HIGH, CRITICAL
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    result_summary = Column(Text, nullable=True)

    user = relationship("User", back_populates="tasks")
    steps = relationship("TaskStep", back_populates="task", cascade="all, delete-orphan", order_by="TaskStep.step_number")
    approvals = relationship("Approval", back_populates="task", cascade="all, delete-orphan")

class ChatSession(Base):
    __tablename__ = "chat_sessions"

    id = Column(String, primary_key=True, default=generate_uuid)
    user_id = Column(String, nullable=False, default="dev_user_1")
    title = Column(String, nullable=True, default="New Chat")
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    messages = relationship("ChatMessage", back_populates="session", cascade="all, delete-orphan", order_by="ChatMessage.created_at")

class ChatMessage(Base):
    __tablename__ = "chat_messages"

    id = Column(String, primary_key=True, default=generate_uuid)
    session_id = Column(String, ForeignKey("chat_sessions.id"), nullable=False)
    sender = Column(String, nullable=False) # 'user' or 'kiko'
    content = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    session = relationship("ChatSession", back_populates="messages")

class TaskStep(Base):
    __tablename__ = "task_steps"

    id = Column(String, primary_key=True, default=generate_uuid)
    task_id = Column(String, ForeignKey("tasks.id"), nullable=False)
    step_number = Column(Integer, nullable=False)
    tool_name = Column(String, nullable=False)
    parameters = Column(JSON, nullable=True)
    status = Column(String, default="PENDING") # PENDING, EXECUTING, WAITING_APPROVAL, COMPLETED, FAILED
    result = Column(Text, nullable=True)
    error = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    task = relationship("Task", back_populates="steps")

class Approval(Base):
    __tablename__ = "approvals"

    id = Column(String, primary_key=True, default=generate_uuid)
    task_id = Column(String, ForeignKey("tasks.id"), nullable=False)
    step_id = Column(String, ForeignKey("task_steps.id"), nullable=True)
    action_description = Column(Text, nullable=False)
    risk_level = Column(String, nullable=False) # LOW, MEDIUM, HIGH, CRITICAL
    tool_name = Column(String, nullable=False)
    parameters = Column(JSON, nullable=True)
    status = Column(String, default="PENDING") # PENDING, APPROVED, REJECTED
    reason = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    resolved_at = Column(DateTime, nullable=True)

    task = relationship("Task", back_populates="approvals")

class MemoryItem(Base):
    __tablename__ = "memory"

    id = Column(String, primary_key=True, default=generate_uuid)
    category = Column(String, nullable=False) # working, episodic, preference, file_location
    key = Column(String, nullable=False)
    value = Column(Text, nullable=False)
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class Document(Base):
    __tablename__ = "documents"

    id = Column(String, primary_key=True, default=generate_uuid)
    file_path = Column(String, unique=True, nullable=False)
    file_name = Column(String, nullable=False)
    file_type = Column(String, nullable=False)
    file_size = Column(Integer, nullable=False)
    indexed_at = Column(DateTime, default=datetime.utcnow)
    status = Column(String, default="INDEXED") # INDEXED, FAILED, REMOVED

class DocumentChunk(Base):
    __tablename__ = "document_chunks"

    id = Column(String, primary_key=True, default=generate_uuid)
    document_id = Column(String, ForeignKey("documents.id"), nullable=False)
    chunk_index = Column(Integer, nullable=False)
    content = Column(Text, nullable=False)
    embedding_id = Column(String, nullable=True)

class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(String, primary_key=True, default=generate_uuid)
    timestamp = Column(DateTime, default=datetime.utcnow)
    user_id = Column(String, nullable=True)
    device_id = Column(String, nullable=True)
    task_id = Column(String, nullable=True)
    tool_name = Column(String, nullable=False)
    action = Column(String, nullable=False)
    risk_level = Column(String, nullable=False)
    approval_status = Column(String, nullable=True)
    result = Column(String, nullable=False) # SUCCESS, FAILED, DENIED

class Integration(Base):
    __tablename__ = "integrations"

    id = Column(String, primary_key=True, default=generate_uuid)
    service_name = Column(String, unique=True, nullable=False) # gmail, outlook, whatsapp, telegram
    is_connected = Column(Boolean, default=False)
    config_json = Column(JSON, nullable=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


# ─── G Mode Models ────────────────────────────────────────────────────────────

class GExperiment(Base):
    """A G Mode autonomous experiment or research task.
    G Mode operates in an isolated workspace and never directly modifies
    the main Alpha codebase. Changes only reach Alpha after explicit user approval.
    """
    __tablename__ = "g_experiments"

    id = Column(String, primary_key=True, default=generate_uuid)
    objective = Column(Text, nullable=False)           # What G Mode is trying to achieve
    mode = Column(String, default="research")          # research, coding, testing, evaluation
    status = Column(
        String, default="PENDING"
    )  # PENDING, RUNNING, PAUSED, COMPLETED, FAILED, CANCELLED, WAITING_APPROVAL
    workspace_path = Column(String, nullable=True)     # Isolated directory for this experiment
    git_branch = Column(String, nullable=True)         # Git branch name (if git used)

    # Resource limits (runtime enforced, not just hints)
    max_runtime_secs = Column(Integer, default=3600)
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Results
    result_summary = Column(Text, nullable=True)
    error_message = Column(Text, nullable=True)
    iteration_count = Column(Integer, default=0)

    logs = relationship("GExperimentLog", back_populates="experiment", cascade="all, delete-orphan", order_by="GExperimentLog.created_at")
    candidates = relationship("GCandidate", back_populates="experiment", cascade="all, delete-orphan")


class GExperimentLog(Base):
    """Structured log entries for G Mode experiments.
    Each log records one iteration of the research/experiment loop.
    """
    __tablename__ = "g_experiment_logs"

    id = Column(String, primary_key=True, default=generate_uuid)
    experiment_id = Column(String, ForeignKey("g_experiments.id"), nullable=False)
    stage = Column(String, nullable=False)    # research, plan, experiment, implement, test, evaluate, record
    message = Column(Text, nullable=False)
    details = Column(JSON, nullable=True)     # Arbitrary structured data for this log entry
    success = Column(Boolean, nullable=True)  # None = in-progress, True/False = completed
    created_at = Column(DateTime, default=datetime.utcnow)

    experiment = relationship("GExperiment", back_populates="logs")


class GCandidate(Base):
    """A candidate improvement produced by G Mode, pending user review and approval.
    A candidate can only be promoted to the main codebase after the user explicitly
    approves it via the /api/v1/gmode/{experiment_id}/candidates/{candidate_id}/approve endpoint.
    Auto-merging is not supported and is not a planned feature.
    """
    __tablename__ = "g_candidates"

    id = Column(String, primary_key=True, default=generate_uuid)
    experiment_id = Column(String, ForeignKey("g_experiments.id"), nullable=False)
    title = Column(String, nullable=False)
    description = Column(Text, nullable=False)
    files_changed = Column(JSON, nullable=True)        # List of relative file paths modified
    diff_summary = Column(Text, nullable=True)         # Human-readable change summary
    test_results = Column(JSON, nullable=True)         # {"passed": int, "failed": int, "details": [...]}
    baseline_score = Column(String, nullable=True)     # Numeric or qualitative baseline metric
    candidate_score = Column(String, nullable=True)    # Numeric or qualitative candidate metric
    known_limitations = Column(Text, nullable=True)
    risk_assessment = Column(Text, nullable=True)

    # Approval workflow
    status = Column(String, default="PENDING_REVIEW")
    # PENDING_REVIEW -> APPROVED | REJECTED
    reviewed_at = Column(DateTime, nullable=True)
    review_notes = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    experiment = relationship("GExperiment", back_populates="candidates")
