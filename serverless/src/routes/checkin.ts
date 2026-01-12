/**
 * Are You Safe? - Check-in Routes
 * 
 * Handles check-in confirmation and snooze operations.
 */

import { Hono } from 'hono';
import { Env, User, CheckinEvent, ConfirmRequest, SnoozeRequest } from '../types';
import { generateUUID } from '../utils/crypto';

export const checkinRoutes = new Hono<{ Bindings: Env }>();

// Helper to get authenticated user
async function getAuthUser(c: any): Promise<User | null> {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return null;
  }
  
  const token = authHeader.substring(7);
  return await c.env.DB.prepare(
    'SELECT * FROM users WHERE auth_token = ?'
  ).bind(token).first<User>();
}

/**
 * POST /api/checkin/confirm
 * 
 * Confirm a check-in event (user is safe).
 * Supports both event_id lookup and scheduled_at lookup.
 * Idempotent - multiple confirms for same event are safe.
 */
checkinRoutes.post('/checkin/confirm', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    const body = await c.req.json<ConfirmRequest>();
    const now = new Date().toISOString();
    const confirmedAt = body.confirmed_at || now;
    
    let event: CheckinEvent | null = null;
    
    // Find the event by event_id or scheduled_at
    if (body.event_id) {
      event = await c.env.DB.prepare(
        'SELECT * FROM checkin_events WHERE event_id = ? AND user_id = ?'
      ).bind(body.event_id, user.user_id).first<CheckinEvent>();
    } else if (body.scheduled_at) {
      event = await c.env.DB.prepare(
        'SELECT * FROM checkin_events WHERE user_id = ? AND scheduled_time = ?'
      ).bind(user.user_id, body.scheduled_at).first<CheckinEvent>();
    } else {
      // Find the most recent pending event for this user
      event = await c.env.DB.prepare(`
        SELECT * FROM checkin_events 
        WHERE user_id = ? AND status IN ('pending', 'snoozed')
        ORDER BY scheduled_time DESC
        LIMIT 1
      `).bind(user.user_id).first<CheckinEvent>();
    }
    
    if (!event) {
      // No pending event found - create a new confirmed event for tracking
      const eventId = generateUUID();
      const scheduledTime = body.scheduled_at || now;
      
      await c.env.DB.prepare(`
        INSERT INTO checkin_events (
          event_id, user_id, scheduled_time, deadline_time, 
          status, confirmed_at, created_at, updated_at
        ) VALUES (?, ?, ?, ?, 'confirmed', ?, ?, ?)
      `).bind(
        eventId,
        user.user_id,
        scheduledTime,
        scheduledTime, // deadline doesn't matter for confirmed events
        confirmedAt,
        now,
        now
      ).run();
      
      // Log the event
      await logEvent(c.env.DB, user.user_id, eventId, 'checkin_confirmed', confirmedAt, 'ok');
      
      return c.json({
        success: true,
        event_id: eventId,
        status: 'confirmed',
        confirmed_at: confirmedAt,
        message: 'Check-in confirmed (new event created)'
      });
    }
    
    // Check if already confirmed (idempotent)
    if (event.status === 'confirmed') {
      return c.json({
        success: true,
        event_id: event.event_id,
        status: 'confirmed',
        confirmed_at: event.confirmed_at,
        message: 'Already confirmed'
      });
    }
    
    // Check if already escalated
    if (event.status === 'alerted') {
      // Still allow confirmation but note that alerts were already sent
      await c.env.DB.prepare(`
        UPDATE checkin_events 
        SET status = 'confirmed', confirmed_at = ?, updated_at = ?
        WHERE event_id = ?
      `).bind(confirmedAt, now, event.event_id).run();
      
      await logEvent(c.env.DB, user.user_id, event.event_id, 'checkin_confirmed_late', confirmedAt, 'ok', {
        note: 'Confirmed after alerts were sent'
      });
      
      return c.json({
        success: true,
        event_id: event.event_id,
        status: 'confirmed',
        confirmed_at: confirmedAt,
        was_escalated: true,
        message: 'Confirmed, but alerts were already sent to your contacts. Please let them know you are safe.'
      });
    }
    
    // Update event to confirmed
    await c.env.DB.prepare(`
      UPDATE checkin_events 
      SET status = 'confirmed', confirmed_at = ?, updated_at = ?
      WHERE event_id = ?
    `).bind(confirmedAt, now, event.event_id).run();
    
    // Log the event
    await logEvent(c.env.DB, user.user_id, event.event_id, 'checkin_confirmed', confirmedAt, 'ok');
    
    return c.json({
      success: true,
      event_id: event.event_id,
      status: 'confirmed',
      confirmed_at: confirmedAt
    });
    
  } catch (error) {
    console.error('Confirm error:', error);
    return c.json({ 
      error: 'Confirmation failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, 500);
  }
});

/**
 * POST /api/checkin/snooze
 * 
 * Snooze a check-in event (delay the deadline).
 * Only allowed once per event.
 */
checkinRoutes.post('/checkin/snooze', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    const body = await c.req.json<SnoozeRequest>();
    const now = new Date().toISOString();
    
    if (!body.event_id) {
      return c.json({ error: 'event_id is required' }, 400);
    }
    
    const snoozeMinutes = body.snooze_minutes || 10;
    if (![5, 10, 15, 30].includes(snoozeMinutes)) {
      return c.json({ error: 'snooze_minutes must be 5, 10, 15, or 30' }, 400);
    }
    
    // Find the event
    const event = await c.env.DB.prepare(
      'SELECT * FROM checkin_events WHERE event_id = ? AND user_id = ?'
    ).bind(body.event_id, user.user_id).first<CheckinEvent>();
    
    if (!event) {
      return c.json({ error: 'Event not found' }, 404);
    }
    
    // Check if already snoozed
    if (event.snooze_count >= 1) {
      return c.json({ 
        error: 'Already snoozed',
        message: 'Each check-in can only be snoozed once'
      }, 400);
    }
    
    // Check if event is in a snoozable state
    if (event.status !== 'pending' && event.status !== 'snoozed') {
      return c.json({ 
        error: 'Cannot snooze',
        message: `Event is already ${event.status}`
      }, 400);
    }
    
    // Calculate new deadline
    const currentDeadline = new Date(event.deadline_time);
    const newDeadline = new Date(currentDeadline.getTime() + snoozeMinutes * 60 * 1000);
    const snoozedUntil = newDeadline.toISOString();
    
    // Update event
    await c.env.DB.prepare(`
      UPDATE checkin_events 
      SET status = 'snoozed', snoozed_until = ?, deadline_time = ?, 
          snooze_count = snooze_count + 1, updated_at = ?
      WHERE event_id = ?
    `).bind(snoozedUntil, snoozedUntil, now, event.event_id).run();
    
    // Log the snooze
    await logEvent(c.env.DB, user.user_id, event.event_id, 'checkin_snoozed', now, 'ok', {
      snooze_minutes: snoozeMinutes,
      new_deadline: snoozedUntil
    });
    
    return c.json({
      success: true,
      event_id: event.event_id,
      status: 'snoozed',
      snoozed_until: snoozedUntil,
      original_deadline: event.deadline_time,
      new_deadline: snoozedUntil
    });
    
  } catch (error) {
    console.error('Snooze error:', error);
    return c.json({ 
      error: 'Snooze failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, 500);
  }
});

/**
 * GET /api/checkin/current
 * 
 * Get the current/next pending check-in event for the user.
 */
checkinRoutes.get('/checkin/current', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    // Find the most recent pending/snoozed event
    const event = await c.env.DB.prepare(`
      SELECT * FROM checkin_events 
      WHERE user_id = ? AND status IN ('pending', 'snoozed')
      ORDER BY scheduled_time DESC
      LIMIT 1
    `).bind(user.user_id).first<CheckinEvent>();
    
    if (!event) {
      return c.json({
        has_pending: false,
        next_checkin: null
      });
    }
    
    return c.json({
      has_pending: true,
      event: {
        event_id: event.event_id,
        scheduled_time: event.scheduled_time,
        deadline_time: event.deadline_time,
        status: event.status,
        snooze_count: event.snooze_count,
        snoozed_until: event.snoozed_until
      }
    });
    
  } catch (error) {
    console.error('Get current checkin error:', error);
    return c.json({ error: 'Failed to get current check-in' }, 500);
  }
});

// Helper function to log events
async function logEvent(
  db: D1Database,
  userId: string,
  eventId: string | null,
  eventType: string,
  eventTime: string,
  result: string,
  details?: object
) {
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
