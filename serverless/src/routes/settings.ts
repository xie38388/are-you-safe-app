/**
 * Are You Safe? - Settings Routes
 * 
 * Handles pause/vacation mode and other settings.
 */

import { Hono } from 'hono';
import { Env, User, PauseRequest } from '../types';
import { generateUUID } from '../utils/crypto';

export const settingsRoutes = new Hono<{ Bindings: Env }>();

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
 * POST /api/settings/pause
 * 
 * Set or clear pause/vacation mode.
 * When paused, no check-ins are scheduled and no alerts are sent.
 */
settingsRoutes.post('/settings/pause', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    const body = await c.req.json<PauseRequest>();
    const now = new Date().toISOString();
    
    // Validate pause_until if provided
    if (body.pause_until) {
      const pauseDate = new Date(body.pause_until);
      if (isNaN(pauseDate.getTime())) {
        return c.json({ error: 'Invalid pause_until date format' }, 400);
      }
      if (pauseDate <= new Date()) {
        return c.json({ error: 'pause_until must be in the future' }, 400);
      }
    }
    
    // Update user's pause status
    await c.env.DB.prepare(`
      UPDATE users SET pause_until = ?, updated_at = ?
      WHERE user_id = ?
    `).bind(body.pause_until, now, user.user_id).run();
    
    // If pausing, mark all pending events as paused
    if (body.pause_until) {
      await c.env.DB.prepare(`
        UPDATE checkin_events 
        SET status = 'paused', updated_at = ?
        WHERE user_id = ? AND status IN ('pending', 'snoozed')
      `).bind(now, user.user_id).run();
      
      // Log the pause
      await logEvent(c.env.DB, user.user_id, null, 'monitoring_paused', now, 'ok', {
        pause_until: body.pause_until
      });
      
      return c.json({
        success: true,
        paused: true,
        pause_until: body.pause_until,
        message: `Monitoring paused until ${body.pause_until}`
      });
    } else {
      // Log the resume
      await logEvent(c.env.DB, user.user_id, null, 'monitoring_resumed', now, 'ok');
      
      return c.json({
        success: true,
        paused: false,
        message: 'Monitoring resumed'
      });
    }
    
  } catch (error) {
    console.error('Pause error:', error);
    return c.json({ 
      error: 'Pause operation failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, 500);
  }
});

/**
 * GET /api/settings/pause
 * 
 * Get current pause status.
 */
settingsRoutes.get('/settings/pause', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const isPaused = user.pause_until && new Date(user.pause_until) > new Date();
  
  return c.json({
    paused: isPaused,
    pause_until: isPaused ? user.pause_until : null
  });
});

/**
 * POST /api/settings/schedule
 * 
 * Update check-in schedule times.
 */
settingsRoutes.post('/settings/schedule', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    const body = await c.req.json<{ times: string[]; grace_minutes?: number }>();
    const now = new Date().toISOString();
    
    // Validate times
    if (!body.times || !Array.isArray(body.times) || body.times.length === 0) {
      return c.json({ error: 'At least one check-in time is required' }, 400);
    }
    
    // Validate time format (HH:MM)
    const timeRegex = /^([01]\d|2[0-3]):([0-5]\d)$/;
    for (const time of body.times) {
      if (!timeRegex.test(time)) {
        return c.json({ 
          error: 'Invalid time format',
          message: `Time "${time}" is not in HH:MM format`
        }, 400);
      }
    }
    
    // Validate grace_minutes if provided
    if (body.grace_minutes !== undefined) {
      if (![5, 10, 15, 30].includes(body.grace_minutes)) {
        return c.json({ error: 'grace_minutes must be 5, 10, 15, or 30' }, 400);
      }
    }
    
    // Update schedule
    const updates: string[] = ['checkin_times = ?', 'updated_at = ?'];
    const values: any[] = [JSON.stringify(body.times), now];
    
    if (body.grace_minutes !== undefined) {
      updates.push('grace_minutes = ?');
      values.push(body.grace_minutes);
    }
    
    values.push(user.user_id);
    
    await c.env.DB.prepare(
      `UPDATE users SET ${updates.join(', ')} WHERE user_id = ?`
    ).bind(...values).run();
    
    return c.json({
      success: true,
      checkin_times: body.times,
      grace_minutes: body.grace_minutes || user.grace_minutes
    });
    
  } catch (error) {
    console.error('Schedule update error:', error);
    return c.json({ 
      error: 'Schedule update failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, 500);
  }
});

/**
 * DELETE /api/settings/account
 * 
 * Delete user account and all associated data.
 */
settingsRoutes.delete('/settings/account', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    // Delete in order due to foreign key constraints
    // Note: With ON DELETE CASCADE, we only need to delete the user
    await c.env.DB.prepare(
      'DELETE FROM users WHERE user_id = ?'
    ).bind(user.user_id).run();
    
    return c.json({
      success: true,
      message: 'Account and all associated data have been deleted'
    });
    
  } catch (error) {
    console.error('Account deletion error:', error);
    return c.json({ 
      error: 'Account deletion failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, 500);
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
