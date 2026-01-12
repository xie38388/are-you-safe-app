/**
 * Are You Safe? - Twilio SMS Service
 * 
 * Handles sending SMS messages via Twilio API.
 * Includes retry logic with exponential backoff.
 */

import { Env, TwilioMessageResponse } from '../types';

interface SendSMSParams {
  to: string;          // E.164 format phone number
  body: string;        // Message content
  env: Env;            // Environment with Twilio credentials
}

interface SendSMSResult {
  success: boolean;
  sid?: string;
  status?: string;
  errorCode?: number;
  errorMessage?: string;
}

/**
 * Send an SMS message via Twilio
 */
export async function sendSMS(params: SendSMSParams): Promise<SendSMSResult> {
  const { to, body, env } = params;
  
  const twilioUrl = `https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}/Messages.json`;
  
  // Create Basic Auth header
  const auth = btoa(`${env.TWILIO_ACCOUNT_SID}:${env.TWILIO_AUTH_TOKEN}`);
  
  // Prepare form data
  const formData = new URLSearchParams();
  formData.append('To', to);
  formData.append('From', env.TWILIO_PHONE_NUMBER);
  formData.append('Body', body);
  
  try {
    const response = await fetch(twilioUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: formData.toString(),
    });
    
    const data = await response.json() as TwilioMessageResponse;
    
    if (response.ok) {
      return {
        success: true,
        sid: data.sid,
        status: data.status,
      };
    } else {
      return {
        success: false,
        errorCode: data.error_code,
        errorMessage: data.error_message || 'Unknown Twilio error',
      };
    }
  } catch (error) {
    return {
      success: false,
      errorMessage: error instanceof Error ? error.message : 'Network error',
    };
  }
}

/**
 * Generate SMS message for missed check-in alert
 */
export function generateAlertMessage(userName: string, scheduledTime: string): string {
  // Format time for display (extract HH:MM from ISO string)
  const time = scheduledTime.split('T')[1]?.substring(0, 5) || scheduledTime;
  
  return `[Are You Safe] ${userName} missed their ${time} safety check-in. ` +
    `Please try to contact them to make sure they're okay. ` +
    `This is an automated message - do not reply.`;
}

/**
 * Calculate next retry time using exponential backoff
 * @param retryCount - Current retry count (0-based)
 * @returns ISO8601 datetime string for next retry
 */
export function calculateNextRetry(retryCount: number): string {
  // Exponential backoff: 1min, 2min, 4min, 8min, etc.
  const delayMinutes = Math.pow(2, retryCount);
  const maxDelayMinutes = 30; // Cap at 30 minutes
  const actualDelay = Math.min(delayMinutes, maxDelayMinutes);
  
  const nextRetry = new Date();
  nextRetry.setMinutes(nextRetry.getMinutes() + actualDelay);
  
  return nextRetry.toISOString();
}

/**
 * Check if a phone number is valid for SMS
 */
export function isValidPhoneForSMS(phone: string): boolean {
  // Must be E.164 format and not empty
  return /^\+[1-9]\d{1,14}$/.test(phone);
}
