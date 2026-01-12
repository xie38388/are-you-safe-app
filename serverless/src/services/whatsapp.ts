/**
 * Are You Safe? - WhatsApp Notification Service
 *
 * Placeholder for WhatsApp notifications via Twilio WhatsApp API.
 * This feature is reserved for future implementation.
 *
 * To enable WhatsApp notifications:
 * 1. Set up Twilio WhatsApp Sender (requires Facebook Business verification)
 * 2. Configure TWILIO_WHATSAPP_NUMBER environment variable
 * 3. Enable WhatsApp templates in Twilio console
 *
 * Documentation: https://www.twilio.com/docs/whatsapp
 */

import { Env } from '../types';

interface WhatsAppResult {
  success: boolean;
  sid?: string;
  status?: string;
  errorMessage?: string;
}

/**
 * Check if WhatsApp is configured and available
 */
export function isWhatsAppEnabled(env: Env): boolean {
  // WhatsApp requires additional environment variables
  // For now, this feature is disabled until properly configured
  return false;

  // When ready to enable, check for:
  // return !!(env.TWILIO_WHATSAPP_NUMBER && env.TWILIO_ACCOUNT_SID && env.TWILIO_AUTH_TOKEN);
}

/**
 * Send WhatsApp message via Twilio API
 *
 * NOTE: This is a placeholder implementation.
 * WhatsApp Business API requires:
 * - Facebook Business verification
 * - Twilio WhatsApp Sender setup
 * - Pre-approved message templates for notifications
 */
export async function sendWhatsAppMessage(params: {
  to: string;
  body: string;
  env: Env;
}): Promise<WhatsAppResult> {
  const { to, body, env } = params;

  // Check if WhatsApp is enabled
  if (!isWhatsAppEnabled(env)) {
    return {
      success: false,
      errorMessage: 'WhatsApp notifications are not enabled',
    };
  }

  // Placeholder for future implementation
  // When implementing, use Twilio's WhatsApp API:
  //
  // const twilioUrl = `https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}/Messages.json`;
  //
  // const formData = new URLSearchParams();
  // formData.append('From', `whatsapp:${env.TWILIO_WHATSAPP_NUMBER}`);
  // formData.append('To', `whatsapp:${to}`);
  // formData.append('Body', body);
  //
  // const response = await fetch(twilioUrl, {
  //   method: 'POST',
  //   headers: {
  //     'Authorization': 'Basic ' + btoa(`${env.TWILIO_ACCOUNT_SID}:${env.TWILIO_AUTH_TOKEN}`),
  //     'Content-Type': 'application/x-www-form-urlencoded',
  //   },
  //   body: formData.toString(),
  // });

  console.log('WhatsApp notification requested but not implemented yet');

  return {
    success: false,
    errorMessage: 'WhatsApp notifications are not yet implemented',
  };
}

/**
 * Generate WhatsApp alert message
 * WhatsApp has specific formatting requirements
 */
export function generateWhatsAppAlertMessage(userName: string, scheduledTime: string): string {
  const time = new Date(scheduledTime).toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  });

  // WhatsApp messages should be concise and clear
  // Emojis are supported and can help with visibility
  return `⚠️ *Safety Alert*

${userName} missed their ${time} check-in with the Are You Safe? app.

This doesn't necessarily mean an emergency, but please try to contact them to make sure they're okay.

_This is an automated message._`;
}

/**
 * Validate WhatsApp phone number format
 * WhatsApp requires E.164 format
 */
export function isValidWhatsAppNumber(phone: string): boolean {
  // Must start with + and country code
  if (!phone.startsWith('+')) {
    return false;
  }

  // Remove + and check if remaining is numeric
  const digits = phone.slice(1);
  if (!/^\d{10,15}$/.test(digits)) {
    return false;
  }

  return true;
}

/**
 * Future: Send template-based WhatsApp message
 * WhatsApp Business API requires pre-approved templates for notifications
 */
export async function sendWhatsAppTemplateMessage(params: {
  to: string;
  templateName: string;
  templateParams: string[];
  env: Env;
}): Promise<WhatsAppResult> {
  // Template messages are required for business-initiated conversations
  // See: https://www.twilio.com/docs/whatsapp/tutorial/send-whatsapp-notification-messages-templates

  console.log('WhatsApp template message requested but not implemented yet');

  return {
    success: false,
    errorMessage: 'WhatsApp template messages are not yet implemented',
  };
}
