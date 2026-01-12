-- Migration: Add multi-level escalation support
-- Level 1 contacts are notified first, Level 2 after a configurable delay

-- Add escalation level tracking to checkin_events
ALTER TABLE checkin_events ADD COLUMN escalation_level INTEGER DEFAULT 0;
-- 0 = not escalated
-- 1 = level 1 contacts notified
-- 2 = level 2 contacts notified

-- Add Level 2 escalation timestamp
ALTER TABLE checkin_events ADD COLUMN level2_escalated_at TEXT;

-- Add user setting for Level 2 delay
ALTER TABLE users ADD COLUMN level2_delay_minutes INTEGER DEFAULT 15;

-- Create index for efficient Level 2 escalation checks
CREATE INDEX IF NOT EXISTS idx_events_level2_pending ON checkin_events(status, escalation_level, escalated_at)
WHERE status = 'alerted' AND escalation_level = 1;
