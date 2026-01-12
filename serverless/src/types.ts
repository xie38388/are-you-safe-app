/**
 * Are You Safe? - Type Definitions
 */

// Cloudflare Workers environment bindings
export interface Env {
  DB: D1Database;
  ENCRYPTION_KEY: string;
  TWILIO_ACCOUNT_SID: string;
  TWILIO_AUTH_TOKEN: string;
  TWILIO_PHONE_NUMBER: string;
}

// Database models
export interface User {
  user_id: string;
  device_id: string;
  timezone: string;
  name: string;
  checkin_times: string; // JSON array
  grace_minutes: number;
  early_reminder_enabled: number;
  early_reminder_minutes: number;
  sms_alerts_enabled: number;
  pause_until: string | null;
  auth_token: string;
  created_at: string;
  updated_at: string;
}

export interface Contact {
  contact_id: string;
  user_id: string;
  phone_enc: string;
  level: number;
  has_app: number;
  created_at: string;
  updated_at: string;
}

export type CheckinStatus = 'pending' | 'confirmed' | 'missed' | 'snoozed' | 'alerted' | 'paused';

export interface CheckinEvent {
  event_id: string;
  user_id: string;
  scheduled_time: string;
  deadline_time: string;
  status: CheckinStatus;
  confirmed_at: string | null;
  snoozed_until: string | null;
  snooze_count: number;
  escalated_at: string | null;
  created_at: string;
  updated_at: string;
}

export type DeliveryStatus = 'pending' | 'sent' | 'delivered' | 'failed';

export interface AlertDelivery {
  delivery_id: string;
  event_id: string;
  contact_id: string;
  channel: string;
  status: DeliveryStatus;
  provider_ref: string | null;
  provider_status: string | null;
  error_message: string | null;
  retry_count: number;
  max_retries: number;
  next_retry_at: string | null;
  sent_at: string | null;
  delivered_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface EventLog {
  log_id: string;
  user_id: string;
  event_id: string | null;
  event_type: string;
  event_time: string;
  result: string;
  details: string | null;
  created_at: string;
}

// API request/response types
export interface RegisterRequest {
  device_id: string;
  timezone?: string;
  name?: string;
  schedule_times?: string[];
  grace_minutes?: number;
  sms_alerts_enabled?: boolean;
}

export interface RegisterResponse {
  user_id: string;
  auth_token: string;
  server_time: string;
}

export interface ContactInput {
  phone_e164: string;
  level: number;
}

export interface ContactsRequest {
  contacts: ContactInput[];
}

export interface ConfirmRequest {
  event_id?: string;
  scheduled_at?: string;
  confirmed_at: string;
}

export interface SnoozeRequest {
  event_id: string;
  snooze_minutes: number;
}

export interface PauseRequest {
  pause_until: string | null;
}

export interface HistoryQuery {
  since?: string;
  until?: string;
  limit?: number;
}

export interface HistoryItem {
  event_id: string;
  scheduled_time: string;
  status: CheckinStatus;
  confirmed_at: string | null;
  escalated_at: string | null;
  contacts_alerted: string[];
}

// Twilio types
export interface TwilioMessageResponse {
  sid: string;
  status: string;
  error_code?: number;
  error_message?: string;
}
