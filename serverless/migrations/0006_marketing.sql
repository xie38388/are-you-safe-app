-- Migration: Add marketing waitlist and event tracking

CREATE TABLE IF NOT EXISTS waitlist_leads (
    lead_id TEXT PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    country TEXT,
    source TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS marketing_events (
    event_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    event_name TEXT NOT NULL,
    path TEXT,
    referrer TEXT,
    user_agent TEXT,
    metadata TEXT,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_waitlist_leads_email ON waitlist_leads(email);
CREATE INDEX IF NOT EXISTS idx_marketing_events_name ON marketing_events(event_name);
CREATE INDEX IF NOT EXISTS idx_marketing_events_session ON marketing_events(session_id);
