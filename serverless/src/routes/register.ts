/**
 * Are You Safe? - Registration Routes
 * 
 * Handles user registration and device setup.
 */

import { Hono } from 'hono';
import { Env, RegisterRequest, RegisterResponse, User } from '../types';
import { generateUUID, generateAuthToken } from '../utils/crypto';

export const registerRoutes = new Hono<{ Bindings: Env }>();

/**
 * POST /api/register
 * 
 * Register a new device or update existing registration.
 * Idempotent - same device_id returns same user_id.
 */
registerRoutes.post('/register', async (c) => {
  try {
    const body = await c.req.json<RegisterRequest>();
    
    // Validate required fields
    if (!body.device_id) {
      return c.json({ error: 'device_id is required' }, 400);
    }
    
    // Check if device already registered
    const existingUser = await c.env.DB.prepare(
      'SELECT * FROM users WHERE device_id = ?'
    ).bind(body.device_id).first<User>();
    
    if (existingUser) {
      // Update existing user's settings if provided
      const updates: string[] = [];
      const values: any[] = [];
      
      if (body.timezone) {
        updates.push('timezone = ?');
        values.push(body.timezone);
      }
      if (body.name) {
        updates.push('name = ?');
        values.push(body.name);
      }
      if (body.schedule_times) {
        updates.push('checkin_times = ?');
        values.push(JSON.stringify(body.schedule_times));
      }
      if (body.grace_minutes !== undefined) {
        updates.push('grace_minutes = ?');
        values.push(body.grace_minutes);
      }
      if (body.sms_alerts_enabled !== undefined) {
        updates.push('sms_alerts_enabled = ?');
        values.push(body.sms_alerts_enabled ? 1 : 0);
      }
      if (body.apns_token) {
        updates.push('apns_token = ?');
        values.push(body.apns_token);
      }

      if (updates.length > 0) {
        updates.push('updated_at = ?');
        values.push(new Date().toISOString());
        values.push(existingUser.user_id);
        
        await c.env.DB.prepare(
          `UPDATE users SET ${updates.join(', ')} WHERE user_id = ?`
        ).bind(...values).run();
      }
      
      const response: RegisterResponse = {
        user_id: existingUser.user_id,
        auth_token: existingUser.auth_token,
        server_time: new Date().toISOString(),
      };
      
      return c.json(response);
    }
    
    // Create new user
    const userId = generateUUID();
    const authToken = generateAuthToken();
    const now = new Date().toISOString();
    
    const checkinTimes = body.schedule_times 
      ? JSON.stringify(body.schedule_times)
      : '["09:00"]';
    
    await c.env.DB.prepare(`
      INSERT INTO users (
        user_id, device_id, timezone, name, checkin_times,
        grace_minutes, sms_alerts_enabled, auth_token, apns_token, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      userId,
      body.device_id,
      body.timezone || 'UTC',
      body.name || 'User',
      checkinTimes,
      body.grace_minutes || 10,
      body.sms_alerts_enabled ? 1 : 0,
      authToken,
      body.apns_token || null,
      now,
      now
    ).run();
    
    const response: RegisterResponse = {
      user_id: userId,
      auth_token: authToken,
      server_time: now,
    };
    
    return c.json(response, 201);
    
  } catch (error) {
    console.error('Registration error:', error);
    return c.json({ 
      error: 'Registration failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, 500);
  }
});

/**
 * GET /api/user
 * 
 * Get current user's profile and settings.
 * Requires authentication.
 */
registerRoutes.get('/user', async (c) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const token = authHeader.substring(7);
  const user = await c.env.DB.prepare(
    'SELECT * FROM users WHERE auth_token = ?'
  ).bind(token).first<User>();
  
  if (!user) {
    return c.json({ error: 'Invalid token' }, 401);
  }
  
  // Return user profile (excluding sensitive fields)
  return c.json({
    user_id: user.user_id,
    timezone: user.timezone,
    name: user.name,
    checkin_times: JSON.parse(user.checkin_times),
    grace_minutes: user.grace_minutes,
    early_reminder_enabled: user.early_reminder_enabled === 1,
    early_reminder_minutes: user.early_reminder_minutes,
    sms_alerts_enabled: user.sms_alerts_enabled === 1,
    pause_until: user.pause_until,
    created_at: user.created_at,
  });
});

/**
 * PUT /api/user
 * 
 * Update current user's settings.
 * Requires authentication.
 */
registerRoutes.put('/user', async (c) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const token = authHeader.substring(7);
  const user = await c.env.DB.prepare(
    'SELECT * FROM users WHERE auth_token = ?'
  ).bind(token).first<User>();
  
  if (!user) {
    return c.json({ error: 'Invalid token' }, 401);
  }
  
  try {
    const body = await c.req.json();
    const updates: string[] = [];
    const values: any[] = [];
    
    if (body.timezone !== undefined) {
      updates.push('timezone = ?');
      values.push(body.timezone);
    }
    if (body.name !== undefined) {
      updates.push('name = ?');
      values.push(body.name);
    }
    if (body.checkin_times !== undefined) {
      updates.push('checkin_times = ?');
      values.push(JSON.stringify(body.checkin_times));
    }
    if (body.grace_minutes !== undefined) {
      updates.push('grace_minutes = ?');
      values.push(body.grace_minutes);
    }
    if (body.early_reminder_enabled !== undefined) {
      updates.push('early_reminder_enabled = ?');
      values.push(body.early_reminder_enabled ? 1 : 0);
    }
    if (body.early_reminder_minutes !== undefined) {
      updates.push('early_reminder_minutes = ?');
      values.push(body.early_reminder_minutes);
    }
    if (body.sms_alerts_enabled !== undefined) {
      updates.push('sms_alerts_enabled = ?');
      values.push(body.sms_alerts_enabled ? 1 : 0);
    }
    if (body.apns_token !== undefined) {
      updates.push('apns_token = ?');
      values.push(body.apns_token);
    }

    if (updates.length === 0) {
      return c.json({ error: 'No fields to update' }, 400);
    }
    
    updates.push('updated_at = ?');
    values.push(new Date().toISOString());
    values.push(user.user_id);
    
    await c.env.DB.prepare(
      `UPDATE users SET ${updates.join(', ')} WHERE user_id = ?`
    ).bind(...values).run();
    
    return c.json({ success: true });
    
  } catch (error) {
    console.error('Update user error:', error);
    return c.json({ error: 'Update failed' }, 500);
  }
});

/**
 * PUT /api/user/token
 *
 * Update APNs device token.
 * Called when app launches or token changes.
 * Requires authentication.
 */
registerRoutes.put('/user/token', async (c) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const token = authHeader.substring(7);
  const user = await c.env.DB.prepare(
    'SELECT * FROM users WHERE auth_token = ?'
  ).bind(token).first<User>();

  if (!user) {
    return c.json({ error: 'Invalid token' }, 401);
  }

  try {
    const body = await c.req.json<{ apns_token: string }>();

    if (!body.apns_token) {
      return c.json({ error: 'apns_token is required' }, 400);
    }

    await c.env.DB.prepare(
      'UPDATE users SET apns_token = ?, updated_at = ? WHERE user_id = ?'
    ).bind(body.apns_token, new Date().toISOString(), user.user_id).run();

    return c.json({ success: true });

  } catch (error) {
    console.error('Update token error:', error);
    return c.json({ error: 'Update failed' }, 500);
  }
});
