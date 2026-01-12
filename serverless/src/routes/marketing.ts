/**
 * Are You Safe? - Marketing Routes
 *
 * Landing page + lightweight event/lead collection for waitlist.
 */

import { Hono } from 'hono';
import { Env } from '../types';
import { generateUUID } from '../utils/crypto';

export const marketingRoutes = new Hono<{ Bindings: Env }>();

const landingPageHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Are You Safe? — Daily safety check-ins</title>
  <style>
    :root {
      color-scheme: light;
      font-family: "Inter", system-ui, -apple-system, sans-serif;
      background: #f7f7fb;
      color: #1b1b1f;
    }
    body {
      margin: 0;
      padding: 0;
    }
    .container {
      max-width: 960px;
      margin: 0 auto;
      padding: 48px 24px 80px;
    }
    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 16px;
    }
    .badge {
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      background: #e9e6ff;
      color: #4d2fd2;
      padding: 6px 10px;
      border-radius: 999px;
      font-weight: 600;
    }
    h1 {
      font-size: clamp(32px, 5vw, 48px);
      margin: 32px 0 16px;
    }
    .subtitle {
      font-size: 18px;
      line-height: 1.6;
      max-width: 640px;
      margin-bottom: 32px;
      color: #3f3f46;
    }
    .cta-row {
      display: flex;
      flex-wrap: wrap;
      gap: 16px;
    }
    .cta {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 14px 24px;
      border-radius: 12px;
      font-weight: 600;
      text-decoration: none;
      border: 1px solid transparent;
    }
    .cta.primary {
      background: #4d2fd2;
      color: #fff;
    }
    .cta.secondary {
      background: #fff;
      border-color: #d4d4d8;
      color: #111827;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 16px;
      margin-top: 40px;
    }
    .card {
      background: #fff;
      border-radius: 16px;
      padding: 20px;
      border: 1px solid #e4e4e7;
      box-shadow: 0 10px 24px rgba(15, 23, 42, 0.06);
    }
    .card h3 {
      margin-top: 0;
      margin-bottom: 8px;
    }
    .disclaimer {
      margin-top: 32px;
      font-size: 14px;
      color: #6b7280;
    }
    form {
      margin-top: 24px;
      display: grid;
      gap: 12px;
      max-width: 420px;
    }
    input, select {
      padding: 12px 14px;
      border-radius: 10px;
      border: 1px solid #d4d4d8;
      font-size: 14px;
    }
    button {
      padding: 12px 14px;
      border-radius: 10px;
      border: none;
      background: #111827;
      color: #fff;
      font-weight: 600;
      cursor: pointer;
    }
    .status {
      font-size: 14px;
      color: #4b5563;
      min-height: 20px;
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="badge">Private Beta</div>
      <span>Are You Safe?</span>
    </header>

    <h1>Daily safety check-ins for people who live alone.</h1>
    <p class="subtitle">
      Set a simple daily check-in schedule. If you miss it, we notify the people you trust
      so they can make sure you’re okay.
    </p>

    <div class="cta-row">
      <a class="cta primary" data-track="cta_testflight" href="https://testflight.apple.com" target="_blank" rel="noreferrer">Join TestFlight</a>
      <a class="cta secondary" data-track="cta_waitlist" href="#waitlist">Join the waitlist</a>
    </div>

    <div class="grid">
      <div class="card">
        <h3>Clear routine</h3>
        <p>Schedule a daily check-in and mark yourself safe in seconds.</p>
      </div>
      <div class="card">
        <h3>Trusted alerts</h3>
        <p>Miss a check-in? We notify your emergency contacts to follow up.</p>
      </div>
      <div class="card">
        <h3>Privacy-first</h3>
        <p>Your contact details stay encrypted. We collect only what’s needed.</p>
      </div>
    </div>

    <section id="waitlist">
      <h2>Get early access</h2>
      <p class="subtitle">Tell us where you are so we can prioritize regions for the beta.</p>
      <form id="waitlist-form">
        <input name="email" type="email" placeholder="Email address" required />
        <input name="country" type="text" placeholder="Country" />
        <button type="submit">Join the waitlist</button>
        <div class="status" id="form-status"></div>
      </form>
    </section>

    <p class="disclaimer">
      Are You Safe? is not a medical or emergency service and does not replace 911/112. In
      an emergency, contact local authorities immediately.
    </p>
  </div>

  <script>
    const sessionKey = 'ays_session_id';
    const sessionId = localStorage.getItem(sessionKey) || crypto.randomUUID();
    localStorage.setItem(sessionKey, sessionId);

    function track(eventName, metadata = {}) {
      navigator.sendBeacon('/api/marketing/event', JSON.stringify({
        event_id: crypto.randomUUID(),
        session_id: sessionId,
        event_name: eventName,
        path: window.location.pathname,
        metadata,
      }));
    }

    track('page_view');

    document.querySelectorAll('[data-track]').forEach((el) => {
      el.addEventListener('click', () => track(el.dataset.track));
    });

    const form = document.getElementById('waitlist-form');
    const status = document.getElementById('form-status');

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      status.textContent = 'Submitting...';

      const formData = new FormData(form);
      const payload = {
        email: formData.get('email'),
        country: formData.get('country') || null,
        session_id: sessionId,
        source: 'landing_page',
      };

      try {
        const response = await fetch('/api/marketing/lead', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        const data = await response.json();

        if (response.ok) {
          status.textContent = data.message || 'Thanks for joining!';
          track('waitlist_submitted');
          form.reset();
        } else {
          status.textContent = data.message || 'Something went wrong. Please try again.';
        }
      } catch (error) {
        status.textContent = 'Network error. Please try again later.';
      }
    });
  </script>
</body>
</html>`;

marketingRoutes.get('/landing', (c) => {
  return c.html(landingPageHtml);
});

marketingRoutes.post('/api/marketing/event', async (c) => {
  try {
    const body = await c.req.json<{
      event_id?: string;
      session_id?: string;
      event_name?: string;
      path?: string;
      metadata?: Record<string, unknown>;
    }>();

    if (!body.session_id || !body.event_name) {
      return c.json({ error: 'session_id and event_name are required' }, 400);
    }

    const eventId = body.event_id || generateUUID();
    const createdAt = new Date().toISOString();

    await c.env.DB.prepare(`
      INSERT OR IGNORE INTO marketing_events (event_id, session_id, event_name, path, referrer, user_agent, metadata, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      eventId,
      body.session_id,
      body.event_name,
      body.path || null,
      c.req.header('Referer') || null,
      c.req.header('User-Agent') || null,
      body.metadata ? JSON.stringify(body.metadata) : null,
      createdAt
    ).run();

    console.log('Marketing event logged', { eventId, eventName: body.event_name });

    return c.json({ success: true });
  } catch (error) {
    console.error('Marketing event error:', error);
    return c.json({ error: 'Failed to log event' }, 500);
  }
});

marketingRoutes.post('/api/marketing/lead', async (c) => {
  try {
    const body = await c.req.json<{
      email?: string;
      country?: string | null;
      source?: string;
      session_id?: string;
    }>();

    if (!body.email) {
      return c.json({ error: 'email is required', message: 'Please provide an email.' }, 400);
    }

    const email = body.email.toLowerCase().trim();

    const existing = await c.env.DB.prepare(
      'SELECT lead_id FROM waitlist_leads WHERE email = ?'
    ).bind(email).first<{ lead_id: string }>();

    if (existing) {
      console.log('Waitlist lead already exists', { email });
      return c.json({
        success: true,
        status: 'already_subscribed',
        message: 'You are already on the waitlist.',
      });
    }

    const leadId = generateUUID();
    const createdAt = new Date().toISOString();

    await c.env.DB.prepare(`
      INSERT INTO waitlist_leads (lead_id, email, country, source, created_at)
      VALUES (?, ?, ?, ?, ?)
    `).bind(
      leadId,
      email,
      body.country || null,
      body.source || 'landing_page',
      createdAt
    ).run();

    console.log('Waitlist lead created', { leadId, email, sessionId: body.session_id || null });

    return c.json({
      success: true,
      status: 'subscribed',
      message: 'Thanks for joining the waitlist! We will be in touch soon.',
    });
  } catch (error) {
    console.error('Waitlist lead error:', error);
    return c.json({ error: 'Failed to save waitlist lead', message: 'Please try again later.' }, 500);
  }
});
