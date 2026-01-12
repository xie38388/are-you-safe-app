/**
 * Are You Safe? - Invite Routes
 *
 * Handles contact invitation and app linking.
 * Allows users to invite contacts to install the app
 * and link their accounts for push notifications.
 */

import { Hono } from 'hono';
import { Env, User, Contact } from '../types';
import { generateUUID } from '../utils/crypto';

export const inviteRoutes = new Hono<{ Bindings: Env }>();

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
 * POST /api/invite/generate
 *
 * Generate an invite code for a contact to link their app.
 * The invite code is valid for 7 days.
 */
inviteRoutes.post('/invite/generate', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  try {
    const body = await c.req.json<{ contact_id?: string }>();

    // Generate a short invite code (6 characters)
    const inviteCode = generateShortCode();
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days
    const now = new Date().toISOString();

    // Store the invite
    const inviteId = generateUUID();
    await c.env.DB.prepare(`
      INSERT INTO invites (invite_id, user_id, contact_id, invite_code, expires_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).bind(
      inviteId,
      user.user_id,
      body.contact_id || null,
      inviteCode,
      expiresAt.toISOString(),
      now
    ).run();

    // Generate deep link URL
    const inviteUrl = `https://areyousafe.app/invite/${inviteCode}`;

    return c.json({
      success: true,
      invite_code: inviteCode,
      invite_url: inviteUrl,
      expires_at: expiresAt.toISOString(),
      message: `Share this link with your contact: ${inviteUrl}`,
    });

  } catch (error) {
    console.error('Generate invite error:', error);
    return c.json({ error: 'Failed to generate invite' }, 500);
  }
});

/**
 * POST /api/invite/accept
 *
 * Accept an invite and link the current user as a contact.
 * Called by the contact after they install the app.
 */
inviteRoutes.post('/invite/accept', async (c) => {
  const acceptingUser = await getAuthUser(c);
  if (!acceptingUser) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  try {
    const body = await c.req.json<{ invite_code: string }>();

    if (!body.invite_code) {
      return c.json({ error: 'invite_code is required' }, 400);
    }

    // Find the invite
    const invite = await c.env.DB.prepare(`
      SELECT i.*, u.name as inviter_name
      FROM invites i
      JOIN users u ON i.user_id = u.user_id
      WHERE i.invite_code = ?
      AND i.expires_at > ?
      AND i.accepted_at IS NULL
    `).bind(body.invite_code, new Date().toISOString()).first<any>();

    if (!invite) {
      return c.json({
        error: 'Invalid or expired invite',
        message: 'This invite code is invalid, expired, or has already been used.'
      }, 400);
    }

    // Don't allow self-linking
    if (invite.user_id === acceptingUser.user_id) {
      return c.json({
        error: 'Cannot accept own invite',
        message: 'You cannot link yourself as your own contact.'
      }, 400);
    }

    const now = new Date().toISOString();

    // Update the contact record if it exists
    if (invite.contact_id) {
      await c.env.DB.prepare(`
        UPDATE contacts
        SET has_app = 1, linked_user_id = ?, apns_token = ?, updated_at = ?
        WHERE contact_id = ?
      `).bind(acceptingUser.user_id, acceptingUser.apns_token, now, invite.contact_id).run();
    } else {
      // Create a new contact entry linked to the accepting user
      const contactId = generateUUID();
      await c.env.DB.prepare(`
        INSERT INTO contacts (contact_id, user_id, phone_enc, level, has_app, linked_user_id, apns_token, created_at, updated_at)
        VALUES (?, ?, '', 1, 1, ?, ?, ?, ?)
      `).bind(
        contactId,
        invite.user_id,
        acceptingUser.user_id,
        acceptingUser.apns_token,
        now,
        now
      ).run();
    }

    // Mark invite as accepted
    await c.env.DB.prepare(`
      UPDATE invites
      SET accepted_at = ?, accepted_by_user_id = ?
      WHERE invite_id = ?
    `).bind(now, acceptingUser.user_id, invite.invite_id).run();

    return c.json({
      success: true,
      linked_to: invite.inviter_name,
      message: `You are now linked as an emergency contact for ${invite.inviter_name}. You will receive push notifications if they miss a check-in.`,
    });

  } catch (error) {
    console.error('Accept invite error:', error);
    return c.json({ error: 'Failed to accept invite' }, 500);
  }
});

/**
 * GET /api/invite/pending
 *
 * Get list of pending (unused) invites for the current user.
 */
inviteRoutes.get('/invite/pending', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  try {
    const invites = await c.env.DB.prepare(`
      SELECT invite_id, invite_code, contact_id, expires_at, created_at
      FROM invites
      WHERE user_id = ?
      AND accepted_at IS NULL
      AND expires_at > ?
      ORDER BY created_at DESC
    `).bind(user.user_id, new Date().toISOString()).all();

    return c.json({
      invites: invites.results,
      count: invites.results.length,
    });

  } catch (error) {
    console.error('Get pending invites error:', error);
    return c.json({ error: 'Failed to get invites' }, 500);
  }
});

/**
 * GET /api/contacts/linked
 *
 * Get list of contacts who have linked their app.
 */
inviteRoutes.get('/contacts/linked', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  try {
    const contacts = await c.env.DB.prepare(`
      SELECT c.contact_id, c.level, c.created_at, u.name as linked_user_name
      FROM contacts c
      LEFT JOIN users u ON c.linked_user_id = u.user_id
      WHERE c.user_id = ?
      AND c.has_app = 1
      ORDER BY c.level ASC
    `).bind(user.user_id).all();

    return c.json({
      contacts: contacts.results,
      count: contacts.results.length,
    });

  } catch (error) {
    console.error('Get linked contacts error:', error);
    return c.json({ error: 'Failed to get linked contacts' }, 500);
  }
});

/**
 * DELETE /api/invite/:inviteCode
 *
 * Cancel a pending invite.
 */
inviteRoutes.delete('/invite/:inviteCode', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const inviteCode = c.req.param('inviteCode');

  try {
    const result = await c.env.DB.prepare(`
      DELETE FROM invites
      WHERE invite_code = ?
      AND user_id = ?
      AND accepted_at IS NULL
    `).bind(inviteCode, user.user_id).run();

    if (result.meta.changes === 0) {
      return c.json({ error: 'Invite not found or already used' }, 404);
    }

    return c.json({ success: true });

  } catch (error) {
    console.error('Delete invite error:', error);
    return c.json({ error: 'Failed to delete invite' }, 500);
  }
});

/**
 * Generate a short alphanumeric code (6 characters)
 */
function generateShortCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Excluding similar chars (0,O,1,I)
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}
