-- Migration: Add invites table for contact app linking
-- This enables users to invite contacts to install the app and link accounts

CREATE TABLE IF NOT EXISTS invites (
    invite_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(user_id),
    contact_id TEXT REFERENCES contacts(contact_id),
    invite_code TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL,
    accepted_at TEXT,
    accepted_by_user_id TEXT REFERENCES users(user_id),
    created_at TEXT NOT NULL,

    -- Indexes for efficient lookups
    CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Index for looking up invites by code
CREATE INDEX IF NOT EXISTS idx_invites_code ON invites(invite_code);

-- Index for looking up user's pending invites
CREATE INDEX IF NOT EXISTS idx_invites_user_pending ON invites(user_id, accepted_at);

-- Index for expiration checks
CREATE INDEX IF NOT EXISTS idx_invites_expires ON invites(expires_at);
