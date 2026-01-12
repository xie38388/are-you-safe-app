/**
 * Are You Safe? - Cloudflare Workers API
 * 
 * Main entry point for the serverless backend.
 * Handles HTTP requests and scheduled cron jobs.
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { registerRoutes } from './routes/register';
import { contactsRoutes } from './routes/contacts';
import { checkinRoutes } from './routes/checkin';
import { settingsRoutes } from './routes/settings';
import { historyRoutes } from './routes/history';
import { debugRoutes } from './routes/debug';
import { handleScheduledCheckins, handleEscalations, handleRetries, handleDataCleanup } from './cron/scheduler';
import { Env } from './types';

const app = new Hono<{ Bindings: Env }>();

// Middleware
app.use('*', logger());
app.use('*', cors({
  origin: '*',
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'Authorization'],
}));

// Health check
app.get('/', (c) => {
  return c.json({
    name: 'Are You Safe? API',
    version: '1.0.0',
    status: 'healthy',
    timestamp: new Date().toISOString(),
  });
});

// API Routes
app.route('/api', registerRoutes);
app.route('/api', contactsRoutes);
app.route('/api', checkinRoutes);
app.route('/api', settingsRoutes);
app.route('/api', historyRoutes);
app.route('/api', debugRoutes);

// Error handling
app.onError((err, c) => {
  console.error('Unhandled error:', err);
  return c.json({
    error: 'Internal Server Error',
    message: err.message,
  }, 500);
});

// 404 handler
app.notFound((c) => {
  return c.json({
    error: 'Not Found',
    message: `Route ${c.req.method} ${c.req.path} not found`,
  }, 404);
});

// Export for Cloudflare Workers
export default {
  fetch: app.fetch,
  
  // Scheduled cron handler - runs every minute
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    console.log('Cron triggered at:', new Date().toISOString());
    
    try {
      // 1. Create pending events for users whose check-in time has arrived
      await handleScheduledCheckins(env);

      // 2. Escalate events that have passed their deadline without response
      await handleEscalations(env);

      // 3. Retry failed SMS deliveries
      await handleRetries(env);

      // 4. Data lifecycle cleanup (runs once daily at midnight UTC)
      await handleDataCleanup(env);

      console.log('Cron completed successfully');
    } catch (error) {
      console.error('Cron error:', error);
    }
  },
};
