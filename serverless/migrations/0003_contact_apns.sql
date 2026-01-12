-- Migration: 0003_contact_apns.sql
-- Description: Add APNs token for contacts who have the app installed

-- Add apns_token column to contacts table
ALTER TABLE contacts ADD COLUMN apns_token TEXT;

-- Add linked_user_id for contacts who are also app users
ALTER TABLE contacts ADD COLUMN linked_user_id TEXT REFERENCES users(user_id);
