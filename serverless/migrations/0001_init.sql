-- Are You Safe? Database Schema
-- Migration: 0001_init.sql
-- Description: Initial database schema for the Are You Safe? app

-- ============================================
-- Users Table
-- ============================================
-- Stores user configuration and preferences
-- Note: We do NOT store real identity info (email, phone) to minimize privacy risk
CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,                    -- UUID generated on registration
    device_id TEXT NOT NULL UNIQUE,              -- Device identifier for idempotent registration
    timezone TEXT NOT NULL DEFAULT 'UTC',        -- User's timezone (e.g., 'America/New_York')
    name TEXT DEFAULT 'User',                    -- Display name (optional, for SMS personalization)
    
    -- Check-in schedule configuration (stored as JSON)
    -- Format: ["09:00", "21:00"] - array of HH:MM times
    checkin_times TEXT NOT NULL DEFAULT '["09:00"]',
    
    -- Grace window configuration
    grace_minutes INTEGER NOT NULL DEFAULT 10,   -- 5, 10, 15, or 30 minutes
    
    -- Notification preferences
    early_reminder_enabled INTEGER NOT NULL DEFAULT 0,  -- 0=false, 1=true
    early_reminder_minutes INTEGER NOT NULL DEFAULT 30, -- Minutes before check-in
    sms_alerts_enabled INTEGER NOT NULL DEFAULT 0,      -- 0=false, 1=true
    
    -- Pause/Vacation mode
    pause_until TEXT,                            -- ISO8601 datetime, NULL if not paused
    
    -- Auth token for API calls
    auth_token TEXT NOT NULL UNIQUE,
    
    -- Timestamps
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Index for efficient lookup by device_id
CREATE INDEX IF NOT EXISTS idx_users_device_id ON users(device_id);

-- ============================================
-- Contacts Table (SMS-enabled contacts only)
-- ============================================
-- Only stores contacts that user has explicitly authorized for SMS alerts
-- Phone numbers are encrypted using ENCRYPTION_KEY env variable
-- Contact names are NEVER stored on server (only locally on device)
CREATE TABLE IF NOT EXISTS contacts (
    contact_id TEXT PRIMARY KEY,                 -- UUID
    user_id TEXT NOT NULL,                       -- Foreign key to users
    phone_enc TEXT NOT NULL,                     -- Encrypted E.164 phone number
    level INTEGER NOT NULL DEFAULT 1,            -- 1 or 2 for escalation priority
    has_app INTEGER NOT NULL DEFAULT 0,          -- 0=false, 1=true (for future use)
    
    -- Timestamps
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Index for efficient lookup by user_id
CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON contacts(user_id);

-- ============================================
-- Check-in Events Table
-- ============================================
-- Records each scheduled check-in and its lifecycle
-- Status flow: pending -> confirmed | missed | snoozed -> alerted
CREATE TABLE IF NOT EXISTS checkin_events (
    event_id TEXT PRIMARY KEY,                   -- UUID, also serves as idempotency key
    user_id TEXT NOT NULL,                       -- Foreign key to users
    
    -- Scheduling
    scheduled_time TEXT NOT NULL,                -- ISO8601 datetime of scheduled check-in
    deadline_time TEXT NOT NULL,                 -- scheduled_time + grace_minutes
    
    -- Status: pending, confirmed, missed, snoozed, alerted, paused
    status TEXT NOT NULL DEFAULT 'pending',
    
    -- Response tracking
    confirmed_at TEXT,                           -- When user confirmed safety
    snoozed_until TEXT,                          -- If snoozed, new deadline
    snooze_count INTEGER NOT NULL DEFAULT 0,     -- Number of times snoozed (max 1 for MVP)
    
    -- Escalation tracking
    escalated_at TEXT,                           -- When alerts were sent to contacts
    
    -- Timestamps
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_events_user_id ON checkin_events(user_id);
CREATE INDEX IF NOT EXISTS idx_events_status ON checkin_events(status);
CREATE INDEX IF NOT EXISTS idx_events_scheduled ON checkin_events(scheduled_time);
CREATE INDEX IF NOT EXISTS idx_events_deadline ON checkin_events(deadline_time);

-- Unique constraint to prevent duplicate events for same user and scheduled time
CREATE UNIQUE INDEX IF NOT EXISTS idx_events_user_scheduled 
    ON checkin_events(user_id, scheduled_time);

-- ============================================
-- Alert Deliveries Table
-- ============================================
-- Records each SMS/notification sent to contacts
-- Supports retry logic with exponential backoff
CREATE TABLE IF NOT EXISTS alert_deliveries (
    delivery_id TEXT PRIMARY KEY,                -- UUID
    event_id TEXT NOT NULL,                      -- Foreign key to checkin_events
    contact_id TEXT NOT NULL,                    -- Foreign key to contacts
    
    -- Delivery channel: sms, push, whatsapp (future)
    channel TEXT NOT NULL DEFAULT 'sms',
    
    -- Status: pending, sent, delivered, failed
    status TEXT NOT NULL DEFAULT 'pending',
    
    -- Provider response
    provider_ref TEXT,                           -- Twilio message SID or similar
    provider_status TEXT,                        -- Provider-specific status
    error_message TEXT,                          -- Error details if failed
    
    -- Retry logic
    retry_count INTEGER NOT NULL DEFAULT 0,
    max_retries INTEGER NOT NULL DEFAULT 3,
    next_retry_at TEXT,                          -- For retry queue processing
    
    -- Timestamps
    sent_at TEXT,                                -- When message was sent
    delivered_at TEXT,                           -- When delivery was confirmed
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    
    FOREIGN KEY (event_id) REFERENCES checkin_events(event_id) ON DELETE CASCADE,
    FOREIGN KEY (contact_id) REFERENCES contacts(contact_id) ON DELETE CASCADE
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_deliveries_event_id ON alert_deliveries(event_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_status ON alert_deliveries(status);
CREATE INDEX IF NOT EXISTS idx_deliveries_retry ON alert_deliveries(next_retry_at);

-- Unique constraint to prevent duplicate deliveries for same event and contact
CREATE UNIQUE INDEX IF NOT EXISTS idx_deliveries_event_contact 
    ON alert_deliveries(event_id, contact_id, channel);

-- ============================================
-- Event Log Table (for History/Replay)
-- ============================================
-- Simplified log for user-facing history view
-- Stores denormalized data for fast queries
CREATE TABLE IF NOT EXISTS event_logs (
    log_id TEXT PRIMARY KEY,                     -- UUID
    user_id TEXT NOT NULL,                       -- Foreign key to users
    event_id TEXT,                               -- Foreign key to checkin_events (optional)
    
    -- Event details
    event_type TEXT NOT NULL,                    -- checkin_confirmed, checkin_missed, alert_sent, etc.
    event_time TEXT NOT NULL,                    -- ISO8601 datetime
    
    -- Result: ok, missed, alerted
    result TEXT NOT NULL DEFAULT 'ok',
    
    -- Additional details (JSON)
    details TEXT,                                -- {"contacts_alerted": ["Bob", "Carol"]}
    
    -- Timestamps
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Indexes for efficient history queries
CREATE INDEX IF NOT EXISTS idx_logs_user_id ON event_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_logs_event_time ON event_logs(event_time);

-- ============================================
-- System Config Table
-- ============================================
-- Global configuration (for future use)
CREATE TABLE IF NOT EXISTS system_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Insert default config
INSERT OR IGNORE INTO system_config (key, value) VALUES 
    ('max_contacts_per_user', '10'),
    ('max_checkins_per_day', '10'),
    ('sms_daily_limit_per_user', '20');
