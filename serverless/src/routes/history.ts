/**
 * Are You Safe? - History Routes
 * 
 * Provides event history and replay functionality.
 */

import { Hono } from 'hono';
import { Env, User, CheckinEvent, EventLog, HistoryQuery } from '../types';

export const historyRoutes = new Hono<{ Bindings: Env }>();

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
 * GET /api/history
 * 
 * Get check-in event history for the user.
 * Supports filtering by date range.
 */
historyRoutes.get('/history', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    const since = c.req.query('since');
    const until = c.req.query('until');
    const limit = parseInt(c.req.query('limit') || '50');
    
    // Build query with optional date filters
    let query = `
      SELECT 
        e.event_id,
        e.scheduled_time,
        e.deadline_time,
        e.status,
        e.confirmed_at,
        e.snoozed_until,
        e.snooze_count,
        e.escalated_at,
        e.created_at
      FROM checkin_events e
      WHERE e.user_id = ?
    `;
    const params: any[] = [user.user_id];
    
    if (since) {
      query += ' AND e.scheduled_time >= ?';
      params.push(since);
    }
    
    if (until) {
      query += ' AND e.scheduled_time <= ?';
      params.push(until);
    }
    
    query += ' ORDER BY e.scheduled_time DESC LIMIT ?';
    params.push(Math.min(limit, 100)); // Cap at 100
    
    const events = await c.env.DB.prepare(query).bind(...params).all<CheckinEvent>();
    
    // For each escalated event, get the alert delivery info
    const eventsWithAlerts = await Promise.all(
      events.results.map(async (event) => {
        let contactsAlerted: string[] = [];
        
        if (event.status === 'alerted' || event.escalated_at) {
          const deliveries = await c.env.DB.prepare(`
            SELECT d.status, d.sent_at
            FROM alert_deliveries d
            WHERE d.event_id = ?
          `).bind(event.event_id).all();
          
          contactsAlerted = deliveries.results
            .filter((d: any) => d.status === 'sent' || d.status === 'delivered')
            .map((d: any) => 'Contact'); // Don't expose contact details
        }
        
        return {
          event_id: event.event_id,
          scheduled_time: event.scheduled_time,
          deadline_time: event.deadline_time,
          status: event.status,
          confirmed_at: event.confirmed_at,
          snoozed_until: event.snoozed_until,
          snooze_count: event.snooze_count,
          escalated_at: event.escalated_at,
          contacts_alerted_count: contactsAlerted.length
        };
      })
    );
    
    return c.json({
      events: eventsWithAlerts,
      count: eventsWithAlerts.length,
      has_more: events.results.length === limit
    });
    
  } catch (error) {
    console.error('History error:', error);
    return c.json({ error: 'Failed to get history' }, 500);
  }
});

/**
 * GET /api/history/:eventId
 * 
 * Get detailed information about a specific event.
 */
historyRoutes.get('/history/:eventId', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const eventId = c.req.param('eventId');
  
  try {
    // Get the event
    const event = await c.env.DB.prepare(`
      SELECT * FROM checkin_events WHERE event_id = ? AND user_id = ?
    `).bind(eventId, user.user_id).first<CheckinEvent>();
    
    if (!event) {
      return c.json({ error: 'Event not found' }, 404);
    }
    
    // Get alert deliveries for this event
    const deliveries = await c.env.DB.prepare(`
      SELECT 
        delivery_id,
        channel,
        status,
        sent_at,
        delivered_at,
        error_message,
        retry_count
      FROM alert_deliveries
      WHERE event_id = ?
    `).bind(eventId).all();
    
    // Get event logs
    const logs = await c.env.DB.prepare(`
      SELECT 
        event_type,
        event_time,
        result,
        details
      FROM event_logs
      WHERE event_id = ?
      ORDER BY event_time ASC
    `).bind(eventId).all<EventLog>();
    
    return c.json({
      event: {
        event_id: event.event_id,
        scheduled_time: event.scheduled_time,
        deadline_time: event.deadline_time,
        status: event.status,
        confirmed_at: event.confirmed_at,
        snoozed_until: event.snoozed_until,
        snooze_count: event.snooze_count,
        escalated_at: event.escalated_at,
        created_at: event.created_at
      },
      deliveries: deliveries.results.map((d: any) => ({
        delivery_id: d.delivery_id,
        channel: d.channel,
        status: d.status,
        sent_at: d.sent_at,
        delivered_at: d.delivered_at,
        error_message: d.error_message,
        retry_count: d.retry_count
      })),
      timeline: logs.results.map((l: any) => ({
        event_type: l.event_type,
        event_time: l.event_time,
        result: l.result,
        details: l.details ? JSON.parse(l.details) : null
      }))
    });
    
  } catch (error) {
    console.error('Event detail error:', error);
    return c.json({ error: 'Failed to get event details' }, 500);
  }
});

/**
 * GET /api/history/stats
 * 
 * Get summary statistics for the user.
 */
historyRoutes.get('/history/stats', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    // Get counts by status
    const stats = await c.env.DB.prepare(`
      SELECT 
        status,
        COUNT(*) as count
      FROM checkin_events
      WHERE user_id = ?
      GROUP BY status
    `).bind(user.user_id).all();
    
    // Get recent streak (consecutive confirmed check-ins)
    const recentEvents = await c.env.DB.prepare(`
      SELECT status FROM checkin_events
      WHERE user_id = ?
      ORDER BY scheduled_time DESC
      LIMIT 30
    `).bind(user.user_id).all<{ status: string }>();
    
    let streak = 0;
    for (const event of recentEvents.results) {
      if (event.status === 'confirmed') {
        streak++;
      } else if (event.status !== 'paused') {
        break;
      }
    }
    
    // Build stats object
    const statusCounts: Record<string, number> = {};
    for (const row of stats.results as any[]) {
      statusCounts[row.status] = row.count;
    }
    
    return c.json({
      total_checkins: Object.values(statusCounts).reduce((a, b) => a + b, 0),
      confirmed: statusCounts['confirmed'] || 0,
      missed: statusCounts['missed'] || 0,
      alerted: statusCounts['alerted'] || 0,
      snoozed: statusCounts['snoozed'] || 0,
      current_streak: streak
    });
    
  } catch (error) {
    console.error('Stats error:', error);
    return c.json({ error: 'Failed to get stats' }, 500);
  }
});

/**
 * GET /api/history/export
 *
 * Export check-in history data for download.
 * Supports JSON and CSV formats.
 */
historyRoutes.get('/history/export', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  try {
    const format = c.req.query('format') || 'json';
    const since = c.req.query('since');
    const until = c.req.query('until');

    // Build query with optional date filters
    let query = `
      SELECT
        e.event_id,
        e.scheduled_time,
        e.deadline_time,
        e.status,
        e.confirmed_at,
        e.snoozed_until,
        e.snooze_count,
        e.escalated_at,
        e.escalation_level,
        e.created_at
      FROM checkin_events e
      WHERE e.user_id = ?
    `;
    const params: any[] = [user.user_id];

    if (since) {
      query += ' AND e.scheduled_time >= ?';
      params.push(since);
    }

    if (until) {
      query += ' AND e.scheduled_time <= ?';
      params.push(until);
    }

    query += ' ORDER BY e.scheduled_time DESC';

    const events = await c.env.DB.prepare(query).bind(...params).all<CheckinEvent>();

    // Get stats
    const stats = await c.env.DB.prepare(`
      SELECT
        status,
        COUNT(*) as count
      FROM checkin_events
      WHERE user_id = ?
      GROUP BY status
    `).bind(user.user_id).all();

    const statusCounts: Record<string, number> = {};
    for (const row of stats.results as any[]) {
      statusCounts[row.status] = row.count;
    }

    // Format data for export
    const exportData = {
      user: {
        name: user.name,
        timezone: user.timezone,
        created_at: user.created_at
      },
      export_date: new Date().toISOString(),
      summary: {
        total_events: events.results.length,
        confirmed: statusCounts['confirmed'] || 0,
        missed: statusCounts['missed'] || 0,
        alerted: statusCounts['alerted'] || 0,
        snoozed: statusCounts['snoozed'] || 0
      },
      events: events.results.map((e: any) => ({
        date: e.scheduled_time.split('T')[0],
        scheduled_time: e.scheduled_time,
        deadline_time: e.deadline_time,
        status: e.status,
        confirmed_at: e.confirmed_at || '',
        escalated_at: e.escalated_at || '',
        snooze_count: e.snooze_count || 0
      }))
    };

    if (format === 'csv') {
      // Generate CSV
      const csvHeader = 'Date,Scheduled Time,Deadline,Status,Confirmed At,Escalated At,Snooze Count\n';
      const csvRows = exportData.events.map((e: any) =>
        `${e.date},${e.scheduled_time},${e.deadline_time},${e.status},${e.confirmed_at},${e.escalated_at},${e.snooze_count}`
      ).join('\n');

      return new Response(csvHeader + csvRows, {
        headers: {
          'Content-Type': 'text/csv',
          'Content-Disposition': `attachment; filename="are-you-safe-export-${new Date().toISOString().split('T')[0]}.csv"`
        }
      });
    }

    return c.json(exportData);

  } catch (error) {
    console.error('Export error:', error);
    return c.json({ error: 'Failed to export data' }, 500);
  }
});
