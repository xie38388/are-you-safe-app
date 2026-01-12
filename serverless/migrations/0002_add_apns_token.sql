-- Migration: 0002_add_apns_token.sql
-- Description: Add APNs device token for remote push notifications

-- Add apns_token column to users table
ALTER TABLE users ADD COLUMN apns_token TEXT;

-- Index for finding users by APNs token (for push delivery)
CREATE INDEX IF NOT EXISTS idx_users_apns_token ON users(apns_token);
