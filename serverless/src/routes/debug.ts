/**
 * Are You Safe? - Debug Routes
 * 
 * Development-only routes for testing and seeding data.
 * These should be disabled in production.
 */

import { Hono } from 'hono';
import { Env, User } from '../types';
import { generateUUID, generateAuthToken, encrypt } from '../utils/crypto';

export const debugRoutes = new Hono<{ Bindings: Env }>();

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
 * POST /api/debug/seed
 * 
 * Seed test data for development.
 * Creates a test user with contacts and sample events.
 */
debugRoutes.post('/debug/seed', async (c) => {
  try {
    const body = await c.req.json<{
      device_id?: string;
      timezone?: string;
      contacts?: { phone: string; level: number }[];
      events?: { status: string; hours_ago: number }[];
    }>();
    
    const now = new Date();
    const nowStr = now.toISOString();
    
    // Create test user
    const userId = generateUUID();
    const authToken = generateAuthToken();
    const deviceId = body.device_id || `test-device-${Date.now()}`;
    
    await c.env.DB.prepare(`
      INSERT INTO users (
        user_id, device_id, timezone, name, checkin_times, 
        grace_minutes, sms_alerts_enabled, auth_token, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      userId,
      deviceId,
      body.timezone || 'America/New_York',
      'Test User',
      '["09:00", "21:00"]',
      10,
      1, // SMS enabled for testing
      authToken,
      nowStr,
      nowStr
    ).run();
    
    // Add test contacts if provided
    const contactIds: string[] = [];
    if (body.contacts && body.contacts.length > 0) {
      for (const contact of body.contacts) {
        const contactId = generateUUID();
        const phoneEnc = await encrypt(contact.phone, c.env.ENCRYPTION_KEY);
        
        await c.env.DB.prepare(`
          INSERT INTO contacts (contact_id, user_id, phone_enc, level, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?)
        `).bind(contactId, userId, phoneEnc, contact.level, nowStr, nowStr).run();
        
        contactIds.push(contactId);
      }
    }
    
    // Create sample events if provided
    const eventIds: string[] = [];
    if (body.events && body.events.length > 0) {
      for (const eventSpec of body.events) {
        const eventId = generateUUID();
        const scheduledTime = new Date(now.getTime() - eventSpec.hours_ago * 60 * 60 * 1000);
        const deadlineTime = new Date(scheduledTime.getTime() + 10 * 60 * 1000);
        
        let confirmedAt = null;
        let escalatedAt = null;
        
        if (eventSpec.status === 'confirmed') {
          confirmedAt = new Date(scheduledTime.getTime() + 5 * 60 * 1000).toISOString();
        } else if (eventSpec.status === 'alerted') {
          escalatedAt = deadlineTime.toISOString();
        }
        
        await c.env.DB.prepare(`
          INSERT INTO checkin_events (
            event_id, user_id, scheduled_time, deadline_time,
            status, confirmed_at, escalated_at, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).bind(
          eventId,
          userId,
          scheduledTime.toISOString(),
          deadlineTime.toISOString(),
          eventSpec.status,
          confirmedAt,
          escalatedAt,
          nowStr,
          nowStr
        ).run();
        
        eventIds.push(eventId);
      }
    }
    
    return c.json({
      success: true,
      user: {
        user_id: userId,
        auth_token: authToken,
        device_id: deviceId
      },
      contacts: contactIds,
      events: eventIds
    });
    
  } catch (error) {
    console.error('Seed error:', error);
    return c.json({ 
      error: 'Seeding failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, 500);
  }
});

/**
 * POST /api/debug/trigger-escalation
 * 
 * Manually trigger escalation for a specific event.
 * Useful for testing SMS delivery.
 */
debugRoutes.post('/debug/trigger-escalation', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    const body = await c.req.json<{ event_id: string }>();
    
    if (!body.event_id) {
      return c.json({ error: 'event_id is required' }, 400);
    }
    
    // Import the escalation handler
    const { triggerEscalation } = await import('../cron/scheduler');
    
    const result = await triggerEscalation(c.env, body.event_id);
    
    return c.json({
      success: true,
      result
    });
    
  } catch (error) {
    console.error('Trigger escalation error:', error);
    return c.json({ 
      error: 'Escalation trigger failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, 500);
  }
});

/**
 * POST /api/debug/create-pending-event
 * 
 * Create a pending check-in event for testing.
 */
debugRoutes.post('/debug/create-pending-event', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    const body = await c.req.json<{ 
      scheduled_time?: string;
      grace_minutes?: number;
    }>();
    
    const now = new Date();
    const scheduledTime = body.scheduled_time 
      ? new Date(body.scheduled_time)
      : now;
    const graceMinutes = body.grace_minutes || user.grace_minutes;
    const deadlineTime = new Date(scheduledTime.getTime() + graceMinutes * 60 * 1000);
    
    const eventId = generateUUID();
    const nowStr = now.toISOString();
    
    await c.env.DB.prepare(`
      INSERT INTO checkin_events (
        event_id, user_id, scheduled_time, deadline_time,
        status, created_at, updated_at
      ) VALUES (?, ?, ?, ?, 'pending', ?, ?)
    `).bind(
      eventId,
      user.user_id,
      scheduledTime.toISOString(),
      deadlineTime.toISOString(),
      nowStr,
      nowStr
    ).run();
    
    return c.json({
      success: true,
      event: {
        event_id: eventId,
        scheduled_time: scheduledTime.toISOString(),
        deadline_time: deadlineTime.toISOString(),
        status: 'pending'
      }
    });
    
  } catch (error) {
    console.error('Create event error:', error);
    return c.json({ 
      error: 'Event creation failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, 500);
  }
});

/**
 * GET /api/debug/db-stats
 * 
 * Get database statistics for debugging.
 */
debugRoutes.get('/debug/db-stats', async (c) => {
  try {
    const users = await c.env.DB.prepare('SELECT COUNT(*) as count FROM users').first<{ count: number }>();
    const contacts = await c.env.DB.prepare('SELECT COUNT(*) as count FROM contacts').first<{ count: number }>();
    const events = await c.env.DB.prepare('SELECT COUNT(*) as count FROM checkin_events').first<{ count: number }>();
    const deliveries = await c.env.DB.prepare('SELECT COUNT(*) as count FROM alert_deliveries').first<{ count: number }>();
    const logs = await c.env.DB.prepare('SELECT COUNT(*) as count FROM event_logs').first<{ count: number }>();
    
    return c.json({
      users: users?.count || 0,
      contacts: contacts?.count || 0,
      events: events?.count || 0,
      deliveries: deliveries?.count || 0,
      logs: logs?.count || 0
    });
    
  } catch (error) {
    console.error('DB stats error:', error);
    return c.json({ error: 'Failed to get stats' }, 500);
  }
});

/**
 * DELETE /api/debug/reset
 * 
 * Reset all data in the database.
 * USE WITH CAUTION - deletes everything!
 */
debugRoutes.delete('/debug/reset', async (c) => {
  try {
    // Delete in order due to foreign key constraints
    await c.env.DB.prepare('DELETE FROM event_logs').run();
    await c.env.DB.prepare('DELETE FROM alert_deliveries').run();
    await c.env.DB.prepare('DELETE FROM checkin_events').run();
    await c.env.DB.prepare('DELETE FROM contacts').run();
    await c.env.DB.prepare('DELETE FROM users').run();
    
    return c.json({
      success: true,
      message: 'All data has been deleted'
    });
    
  } catch (error) {
    console.error('Reset error:', error);
    return c.json({ error: 'Reset failed' }, 500);
  }
});
