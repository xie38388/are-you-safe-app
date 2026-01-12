/**
 * Are You Safe? - Contacts Routes
 * 
 * Handles SMS-enabled contact management.
 * Phone numbers are encrypted before storage.
 */

import { Hono } from 'hono';
import { Env, User, Contact, ContactsRequest } from '../types';
import { encrypt, decrypt, generateUUID, isValidE164 } from '../utils/crypto';

export const contactsRoutes = new Hono<{ Bindings: Env }>();

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
 * POST /api/contacts/sms
 * 
 * Upload contacts for SMS alerts.
 * Only called when user has enabled SMS alerts and consented.
 * Phone numbers are encrypted before storage.
 */
contactsRoutes.post('/contacts/sms', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  // Check if SMS alerts are enabled
  if (!user.sms_alerts_enabled) {
    return c.json({ 
      error: 'SMS alerts not enabled',
      message: 'Please enable SMS alerts in settings before adding contacts'
    }, 400);
  }
  
  try {
    const body = await c.req.json<ContactsRequest>();
    
    if (!body.contacts || !Array.isArray(body.contacts)) {
      return c.json({ error: 'contacts array is required' }, 400);
    }
    
    // Validate all phone numbers first
    for (const contact of body.contacts) {
      if (!isValidE164(contact.phone_e164)) {
        return c.json({ 
          error: 'Invalid phone number format',
          message: `Phone number ${contact.phone_e164} is not in E.164 format`
        }, 400);
      }
      if (contact.level !== 1 && contact.level !== 2) {
        return c.json({ 
          error: 'Invalid contact level',
          message: 'Contact level must be 1 or 2'
        }, 400);
      }
    }
    
    // Delete existing contacts for this user
    await c.env.DB.prepare(
      'DELETE FROM contacts WHERE user_id = ?'
    ).bind(user.user_id).run();
    
    // Insert new contacts with encrypted phone numbers
    const now = new Date().toISOString();
    const insertedContacts: { contact_id: string; level: number }[] = [];
    
    for (const contact of body.contacts) {
      const contactId = generateUUID();
      const phoneEnc = await encrypt(contact.phone_e164, c.env.ENCRYPTION_KEY);
      
      await c.env.DB.prepare(`
        INSERT INTO contacts (contact_id, user_id, phone_enc, level, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `).bind(
        contactId,
        user.user_id,
        phoneEnc,
        contact.level,
        now,
        now
      ).run();
      
      insertedContacts.push({ contact_id: contactId, level: contact.level });
    }
    
    return c.json({
      success: true,
      contacts_count: insertedContacts.length,
      contacts: insertedContacts
    });
    
  } catch (error) {
    console.error('Contacts upload error:', error);
    return c.json({ 
      error: 'Failed to save contacts',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, 500);
  }
});

/**
 * GET /api/contacts/sms
 * 
 * Get list of SMS-enabled contacts (without phone numbers for privacy).
 */
contactsRoutes.get('/contacts/sms', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    const contacts = await c.env.DB.prepare(
      'SELECT contact_id, level, has_app, created_at FROM contacts WHERE user_id = ?'
    ).bind(user.user_id).all<Contact>();
    
    return c.json({
      contacts: contacts.results.map(c => ({
        contact_id: c.contact_id,
        level: c.level,
        has_app: c.has_app === 1,
        created_at: c.created_at
      })),
      count: contacts.results.length
    });
    
  } catch (error) {
    console.error('Get contacts error:', error);
    return c.json({ error: 'Failed to get contacts' }, 500);
  }
});

/**
 * DELETE /api/contacts/sms
 * 
 * Delete all SMS-enabled contacts for the user.
 */
contactsRoutes.delete('/contacts/sms', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  try {
    await c.env.DB.prepare(
      'DELETE FROM contacts WHERE user_id = ?'
    ).bind(user.user_id).run();
    
    return c.json({ success: true });
    
  } catch (error) {
    console.error('Delete contacts error:', error);
    return c.json({ error: 'Failed to delete contacts' }, 500);
  }
});

/**
 * DELETE /api/contacts/sms/:contactId
 * 
 * Delete a specific contact.
 */
contactsRoutes.delete('/contacts/sms/:contactId', async (c) => {
  const user = await getAuthUser(c);
  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const contactId = c.req.param('contactId');
  
  try {
    const result = await c.env.DB.prepare(
      'DELETE FROM contacts WHERE contact_id = ? AND user_id = ?'
    ).bind(contactId, user.user_id).run();
    
    if (result.meta.changes === 0) {
      return c.json({ error: 'Contact not found' }, 404);
    }
    
    return c.json({ success: true });
    
  } catch (error) {
    console.error('Delete contact error:', error);
    return c.json({ error: 'Failed to delete contact' }, 500);
  }
});
