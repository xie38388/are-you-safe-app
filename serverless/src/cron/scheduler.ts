/**
 * Are You Safe? - Cron Scheduler
 * 
 * Handles scheduled tasks:
 * 1. Creating pending check-in events when scheduled time arrives
 * 2. Escalating missed check-ins to contacts
 * 3. Retrying failed SMS deliveries
 */

import { Env, User, CheckinEvent, Contact, AlertDelivery } from '../types';
import { generateUUID, decrypt } from '../utils/crypto';
import { sendSMS, generateAlertMessage, calculateNextRetry } from '../services/twilio';
import { sendCheckinReminder, sendCheckinReminderFollowup, sendContactAlert } from '../services/apns';

/**
 * Handle scheduled check-ins
 * Creates pending events for users whose check-in time has arrived
 */
export async function handleScheduledCheckins(env: Env): Promise<void> {
  const now = new Date();
  const currentTime = now.toTimeString().substring(0, 5); // HH:MM format
  
  console.log(`Checking for scheduled check-ins at ${currentTime}`);
  
  // Get all active users (not paused)
  const users = await env.DB.prepare(`
    SELECT * FROM users 
    WHERE pause_until IS NULL OR pause_until < ?
  `).bind(now.toISOString()).all<User>();
  
  for (const user of users.results) {
    try {
      // Parse check-in times
      const checkinTimes: string[] = JSON.parse(user.checkin_times);
      
      // Check if current time matches any scheduled time
      // Allow 1-minute window for cron timing
      for (const scheduledTime of checkinTimes) {
        if (isTimeMatch(currentTime, scheduledTime)) {
          // Check if event already exists for this time slot today
          const todayStart = new Date(now);
          todayStart.setHours(0, 0, 0, 0);
          
          const existingEvent = await env.DB.prepare(`
            SELECT event_id FROM checkin_events 
            WHERE user_id = ? 
            AND scheduled_time >= ? 
            AND scheduled_time LIKE ?
          `).bind(
            user.user_id,
            todayStart.toISOString(),
            `%T${scheduledTime}%`
          ).first();
          
          if (!existingEvent) {
            // Create new pending event
            await createPendingEvent(env, user, scheduledTime);
          }
        }
      }
    } catch (error) {
      console.error(`Error processing user ${user.user_id}:`, error);
    }
  }
}

/**
 * Create a pending check-in event for a user
 */
async function createPendingEvent(env: Env, user: User, timeStr: string): Promise<void> {
  const now = new Date();
  const eventId = generateUUID();

  // Parse the scheduled time for today in user's timezone
  // For simplicity, we'll use UTC and let the client handle timezone display
  const [hours, minutes] = timeStr.split(':').map(Number);
  const scheduledTime = new Date(now);
  scheduledTime.setHours(hours, minutes, 0, 0);

  // If the scheduled time is in the past (edge case), skip
  if (scheduledTime < now) {
    return;
  }

  const deadlineTime = new Date(scheduledTime.getTime() + user.grace_minutes * 60 * 1000);

  await env.DB.prepare(`
    INSERT INTO checkin_events (
      event_id, user_id, scheduled_time, deadline_time,
      status, created_at, updated_at
    ) VALUES (?, ?, ?, ?, 'pending', ?, ?)
  `).bind(
    eventId,
    user.user_id,
    scheduledTime.toISOString(),
    deadlineTime.toISOString(),
    now.toISOString(),
    now.toISOString()
  ).run();

  console.log(`Created pending event ${eventId} for user ${user.user_id} at ${scheduledTime.toISOString()}`);

  // Send remote push notification as backup to local notification
  if (user.apns_token) {
    try {
      await sendCheckinReminder({
        deviceToken: user.apns_token,
        userName: user.name,
        graceMinutes: user.grace_minutes,
        eventId: eventId,
        scheduledTime: scheduledTime.toISOString(),
        env,
      });
      console.log(`Sent push notification to user ${user.user_id}`);
    } catch (error) {
      console.error(`Failed to send push notification to user ${user.user_id}:`, error);
    }
  }

  // Log the event
  await logEvent(env.DB, user.user_id, eventId, 'checkin_scheduled', now.toISOString(), 'ok', {
    scheduled_time: scheduledTime.toISOString(),
    deadline_time: deadlineTime.toISOString()
  });
}

/**
 * Handle escalations for missed check-ins
 * Sends SMS alerts to contacts for events past their deadline
 */
export async function handleEscalations(env: Env): Promise<void> {
  const now = new Date();
  
  console.log('Checking for events to escalate');
  
  // Find events that are past deadline and not yet escalated
  const overdueEvents = await env.DB.prepare(`
    SELECT e.*, u.name as user_name, u.sms_alerts_enabled
    FROM checkin_events e
    JOIN users u ON e.user_id = u.user_id
    WHERE e.status IN ('pending', 'snoozed')
    AND e.deadline_time < ?
    AND (u.pause_until IS NULL OR u.pause_until < ?)
  `).bind(now.toISOString(), now.toISOString()).all();
  
  for (const event of overdueEvents.results as any[]) {
    try {
      await triggerEscalation(env, event.event_id);
    } catch (error) {
      console.error(`Error escalating event ${event.event_id}:`, error);
    }
  }
}

/**
 * Trigger escalation for a specific event
 * Sends SMS to all contacts
 */
export async function triggerEscalation(env: Env, eventId: string): Promise<{
  event_id: string;
  contacts_notified: number;
  deliveries: { contact_id: string; status: string; error?: string }[];
}> {
  const now = new Date();
  const nowStr = now.toISOString();
  
  // Get the event with user info
  const event = await env.DB.prepare(`
    SELECT e.*, u.name as user_name, u.sms_alerts_enabled
    FROM checkin_events e
    JOIN users u ON e.user_id = u.user_id
    WHERE e.event_id = ?
  `).bind(eventId).first<CheckinEvent & { user_name: string; sms_alerts_enabled: number }>();
  
  if (!event) {
    throw new Error('Event not found');
  }
  
  // Update event status to alerted
  await env.DB.prepare(`
    UPDATE checkin_events 
    SET status = 'alerted', escalated_at = ?, updated_at = ?
    WHERE event_id = ?
  `).bind(nowStr, nowStr, eventId).run();
  
  // Log the escalation
  await logEvent(env.DB, event.user_id, eventId, 'checkin_escalated', nowStr, 'missed');
  
  const deliveries: { contact_id: string; status: string; error?: string }[] = [];
  
  // Check if SMS alerts are enabled
  if (!event.sms_alerts_enabled) {
    console.log(`SMS alerts not enabled for user ${event.user_id}`);
    return { event_id: eventId, contacts_notified: 0, deliveries };
  }
  
  // Get all contacts for this user
  const contacts = await env.DB.prepare(`
    SELECT * FROM contacts WHERE user_id = ? ORDER BY level ASC
  `).bind(event.user_id).all<Contact>();
  
  if (contacts.results.length === 0) {
    console.log(`No contacts found for user ${event.user_id}`);
    return { event_id: eventId, contacts_notified: 0, deliveries };
  }
  
  // Generate alert message
  const message = generateAlertMessage(event.user_name || 'Your contact', event.scheduled_time);
  
  // Send SMS and/or push notifications to all contacts (MVP: all at once, no level-based delay)
  for (const contact of contacts.results) {
    try {
      // Check if SMS delivery already exists (idempotency)
      const existingDelivery = await env.DB.prepare(`
        SELECT delivery_id FROM alert_deliveries
        WHERE event_id = ? AND contact_id = ? AND channel = 'sms'
      `).bind(eventId, contact.contact_id).first();

      if (existingDelivery) {
        console.log(`Delivery already exists for event ${eventId}, contact ${contact.contact_id}`);
        deliveries.push({ contact_id: contact.contact_id, status: 'already_exists' });
        continue;
      }

      // Send push notification if contact has the app installed
      if (contact.has_app && contact.apns_token) {
        try {
          await sendContactAlert({
            deviceToken: contact.apns_token,
            userName: event.user_name || 'Your contact',
            scheduledTime: event.scheduled_time,
            env,
          });
          console.log(`Push notification sent to contact ${contact.contact_id}`);

          // Record push delivery
          const pushDeliveryId = generateUUID();
          await env.DB.prepare(`
            INSERT INTO alert_deliveries (
              delivery_id, event_id, contact_id, channel, status, sent_at, created_at, updated_at
            ) VALUES (?, ?, ?, 'push', 'sent', ?, ?, ?)
          `).bind(pushDeliveryId, eventId, contact.contact_id, nowStr, nowStr, nowStr).run();
        } catch (pushError) {
          console.error(`Push notification failed for contact ${contact.contact_id}:`, pushError);
        }
      }

      // Decrypt phone number
      const phone = await decrypt(contact.phone_enc, env.ENCRYPTION_KEY);

      // Create SMS delivery record
      const deliveryId = generateUUID();
      await env.DB.prepare(`
        INSERT INTO alert_deliveries (
          delivery_id, event_id, contact_id, channel, status, created_at, updated_at
        ) VALUES (?, ?, ?, 'sms', 'pending', ?, ?)
      `).bind(deliveryId, eventId, contact.contact_id, nowStr, nowStr).run();

      // Send SMS
      const result = await sendSMS({ to: phone, body: message, env });

      if (result.success) {
        // Update delivery as sent
        await env.DB.prepare(`
          UPDATE alert_deliveries
          SET status = 'sent', provider_ref = ?, provider_status = ?, sent_at = ?, updated_at = ?
          WHERE delivery_id = ?
        `).bind(result.sid, result.status, nowStr, nowStr, deliveryId).run();

        deliveries.push({ contact_id: contact.contact_id, status: 'sent' });
        console.log(`SMS sent to contact ${contact.contact_id}`);
      } else {
        // Update delivery as failed with retry
        const nextRetry = calculateNextRetry(0);
        await env.DB.prepare(`
          UPDATE alert_deliveries
          SET status = 'failed', error_message = ?, next_retry_at = ?, updated_at = ?
          WHERE delivery_id = ?
        `).bind(result.errorMessage, nextRetry, nowStr, deliveryId).run();

        deliveries.push({ contact_id: contact.contact_id, status: 'failed', error: result.errorMessage });
        console.error(`SMS failed for contact ${contact.contact_id}: ${result.errorMessage}`);
      }

    } catch (error) {
      console.error(`Error sending to contact ${contact.contact_id}:`, error);
      deliveries.push({
        contact_id: contact.contact_id,
        status: 'error',
        error: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  }
  
  // Log contacts alerted
  await logEvent(env.DB, event.user_id, eventId, 'contacts_alerted', nowStr, 'ok', {
    contacts_count: deliveries.filter(d => d.status === 'sent').length
  });
  
  return {
    event_id: eventId,
    contacts_notified: deliveries.filter(d => d.status === 'sent').length,
    deliveries
  };
}

/**
 * Handle retries for failed SMS deliveries
 */
export async function handleRetries(env: Env): Promise<void> {
  const now = new Date();
  
  console.log('Checking for SMS retries');
  
  // Find failed deliveries that are due for retry
  const pendingRetries = await env.DB.prepare(`
    SELECT d.*, c.phone_enc, e.scheduled_time, u.name as user_name
    FROM alert_deliveries d
    JOIN contacts c ON d.contact_id = c.contact_id
    JOIN checkin_events e ON d.event_id = e.event_id
    JOIN users u ON e.user_id = u.user_id
    WHERE d.status = 'failed'
    AND d.retry_count < d.max_retries
    AND d.next_retry_at <= ?
  `).bind(now.toISOString()).all();
  
  for (const delivery of pendingRetries.results as any[]) {
    try {
      // Decrypt phone number
      const phone = await decrypt(delivery.phone_enc, env.ENCRYPTION_KEY);
      
      // Generate message
      const message = generateAlertMessage(delivery.user_name || 'Your contact', delivery.scheduled_time);
      
      // Retry SMS
      const result = await sendSMS({ to: phone, body: message, env });
      
      const nowStr = now.toISOString();
      
      if (result.success) {
        await env.DB.prepare(`
          UPDATE alert_deliveries 
          SET status = 'sent', provider_ref = ?, provider_status = ?, 
              sent_at = ?, next_retry_at = NULL, updated_at = ?
          WHERE delivery_id = ?
        `).bind(result.sid, result.status, nowStr, nowStr, delivery.delivery_id).run();
        
        console.log(`Retry successful for delivery ${delivery.delivery_id}`);
      } else {
        const newRetryCount = delivery.retry_count + 1;
        const nextRetry = newRetryCount < delivery.max_retries 
          ? calculateNextRetry(newRetryCount)
          : null;
        
        await env.DB.prepare(`
          UPDATE alert_deliveries 
          SET retry_count = ?, error_message = ?, next_retry_at = ?, updated_at = ?
          WHERE delivery_id = ?
        `).bind(newRetryCount, result.errorMessage, nextRetry, nowStr, delivery.delivery_id).run();
        
        console.log(`Retry ${newRetryCount} failed for delivery ${delivery.delivery_id}`);
      }
      
    } catch (error) {
      console.error(`Error retrying delivery ${delivery.delivery_id}:`, error);
    }
  }
}

/**
 * Check if two time strings match (within 1 minute tolerance)
 */
function isTimeMatch(current: string, scheduled: string): boolean {
  const [currentH, currentM] = current.split(':').map(Number);
  const [scheduledH, scheduledM] = scheduled.split(':').map(Number);
  
  const currentMinutes = currentH * 60 + currentM;
  const scheduledMinutes = scheduledH * 60 + scheduledM;
  
  // Allow 1 minute tolerance for cron timing
  return Math.abs(currentMinutes - scheduledMinutes) <= 1;
}

/**
 * Helper function to log events
 */
async function logEvent(
  db: D1Database,
  userId: string,
  eventId: string | null,
  eventType: string,
  eventTime: string,
  result: string,
  details?: object
): Promise<void> {
  const logId = generateUUID();
  await db.prepare(`
    INSERT INTO event_logs (log_id, user_id, event_id, event_type, event_time, result, details, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    logId,
    userId,
    eventId,
    eventType,
    eventTime,
    result,
    details ? JSON.stringify(details) : null,
    new Date().toISOString()
  ).run();
}

/**
 * Data lifecycle management - cleanup old data
 * Runs daily to remove data older than retention period
 */
export async function handleDataCleanup(env: Env): Promise<{
  eventsDeleted: number;
  logsDeleted: number;
  deliveriesDeleted: number;
}> {
  const now = new Date();

  // Only run cleanup once per day (at midnight UTC hour)
  if (now.getUTCHours() !== 0 || now.getUTCMinutes() > 5) {
    return { eventsDeleted: 0, logsDeleted: 0, deliveriesDeleted: 0 };
  }

  console.log('Running data cleanup...');

  // Retention periods (in days)
  const EVENT_RETENTION_DAYS = 180; // 6 months
  const LOG_RETENTION_DAYS = 90;    // 3 months
  const DELIVERY_RETENTION_DAYS = 30; // 1 month

  const eventCutoff = new Date(now.getTime() - EVENT_RETENTION_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const logCutoff = new Date(now.getTime() - LOG_RETENTION_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const deliveryCutoff = new Date(now.getTime() - DELIVERY_RETENTION_DAYS * 24 * 60 * 60 * 1000).toISOString();

  let eventsDeleted = 0;
  let logsDeleted = 0;
  let deliveriesDeleted = 0;

  try {
    // Delete old check-in events (keep recent ones for history)
    const eventResult = await env.DB.prepare(`
      DELETE FROM checkin_events
      WHERE created_at < ?
      AND status NOT IN ('pending', 'snoozed')
    `).bind(eventCutoff).run();
    eventsDeleted = eventResult.meta.changes || 0;

    // Delete old event logs
    const logResult = await env.DB.prepare(`
      DELETE FROM event_logs
      WHERE created_at < ?
    `).bind(logCutoff).run();
    logsDeleted = logResult.meta.changes || 0;

    // Delete old alert deliveries
    const deliveryResult = await env.DB.prepare(`
      DELETE FROM alert_deliveries
      WHERE created_at < ?
    `).bind(deliveryCutoff).run();
    deliveriesDeleted = deliveryResult.meta.changes || 0;

    console.log(`Cleanup complete: ${eventsDeleted} events, ${logsDeleted} logs, ${deliveriesDeleted} deliveries deleted`);

  } catch (error) {
    console.error('Data cleanup error:', error);
  }

  return { eventsDeleted, logsDeleted, deliveriesDeleted };
}
