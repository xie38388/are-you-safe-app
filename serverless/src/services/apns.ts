/**
 * Are You Safe? - APNs Push Notification Service
 *
 * Sends push notifications via Apple Push Notification service (APNs)
 * Uses JWT (token-based) authentication
 */

import { Env } from '../types';

interface APNsPayload {
  aps: {
    alert: {
      title: string;
      body: string;
    };
    sound?: string;
    badge?: number;
    category?: string;
    'thread-id'?: string;
    'interruption-level'?: 'passive' | 'active' | 'time-sensitive' | 'critical';
    'relevance-score'?: number;
  };
  // Custom data
  type?: string;
  event_id?: string;
  scheduled_time?: string;
}

interface APNsResult {
  success: boolean;
  apnsId?: string;
  statusCode?: number;
  errorReason?: string;
}

/**
 * Generate JWT for APNs authentication
 */
async function generateAPNsJWT(env: Env): Promise<string> {
  const header = {
    alg: 'ES256',
    kid: env.APNS_KEY_ID,
  };

  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: env.APNS_TEAM_ID,
    iat: now,
  };

  // Base64URL encode header and payload
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));

  // Sign with ES256 (ECDSA P-256)
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await signES256(signingInput, env.APNS_PRIVATE_KEY);

  return `${signingInput}.${signature}`;
}

/**
 * Base64URL encode
 */
function base64UrlEncode(str: string): string {
  const base64 = btoa(str);
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

/**
 * Sign data with ES256 (ECDSA using P-256 curve)
 */
async function signES256(data: string, privateKeyPEM: string): Promise<string> {
  // Parse PEM private key
  const pemContents = privateKeyPEM
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');

  const binaryKey = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0));

  // Import the key
  const key = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    {
      name: 'ECDSA',
      namedCurve: 'P-256',
    },
    false,
    ['sign']
  );

  // Sign the data
  const encoder = new TextEncoder();
  const dataBuffer = encoder.encode(data);

  const signature = await crypto.subtle.sign(
    {
      name: 'ECDSA',
      hash: 'SHA-256',
    },
    key,
    dataBuffer
  );

  // Convert to base64url
  const signatureArray = new Uint8Array(signature);
  const base64 = btoa(String.fromCharCode(...signatureArray));
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

/**
 * Send push notification via APNs
 */
export async function sendPushNotification(params: {
  deviceToken: string;
  title: string;
  body: string;
  category?: string;
  threadId?: string;
  customData?: Record<string, string>;
  env: Env;
}): Promise<APNsResult> {
  const { deviceToken, title, body, category, threadId, customData, env } = params;

  // Check if APNs is configured
  if (!env.APNS_KEY_ID || !env.APNS_TEAM_ID || !env.APNS_PRIVATE_KEY || !env.APNS_BUNDLE_ID) {
    console.log('APNs not configured, skipping push notification');
    return { success: false, errorReason: 'APNs not configured' };
  }

  try {
    // Generate JWT
    const jwt = await generateAPNsJWT(env);

    // Build payload
    const payload: APNsPayload = {
      aps: {
        alert: { title, body },
        sound: 'default',
        category: category || 'CHECKIN_REMINDER',
        'interruption-level': 'time-sensitive',
        'relevance-score': 1.0,
      },
      ...customData,
    };

    if (threadId) {
      payload.aps['thread-id'] = threadId;
    }

    // APNs endpoint (production)
    const apnsHost = 'api.push.apple.com';
    const url = `https://${apnsHost}/3/device/${deviceToken}`;

    // Send request
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `bearer ${jwt}`,
        'apns-topic': env.APNS_BUNDLE_ID,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'apns-expiration': '0',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    const apnsId = response.headers.get('apns-id') || undefined;

    if (response.ok) {
      console.log(`Push notification sent successfully: ${apnsId}`);
      return { success: true, apnsId, statusCode: response.status };
    } else {
      const errorBody = await response.json().catch(() => ({})) as { reason?: string };
      const errorReason = errorBody.reason || `HTTP ${response.status}`;
      console.error(`APNs error: ${errorReason}`);
      return { success: false, apnsId, statusCode: response.status, errorReason };
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    console.error(`APNs request failed: ${errorMessage}`);
    return { success: false, errorReason: errorMessage };
  }
}

/**
 * Send check-in reminder push notification
 */
export async function sendCheckinReminder(params: {
  deviceToken: string;
  userName: string;
  graceMinutes: number;
  eventId: string;
  scheduledTime: string;
  env: Env;
}): Promise<APNsResult> {
  const { deviceToken, userName, graceMinutes, eventId, scheduledTime, env } = params;

  return sendPushNotification({
    deviceToken,
    title: 'Are You Safe?',
    body: `Please tap 'I\'m Safe' to confirm you're okay. [${graceMinutes} min window]`,
    category: 'CHECKIN_REMINDER',
    customData: {
      type: 'checkin',
      event_id: eventId,
      scheduled_time: scheduledTime,
    },
    env,
  });
}

/**
 * Send reminder (halfway through grace window)
 */
export async function sendCheckinReminderFollowup(params: {
  deviceToken: string;
  eventId: string;
  env: Env;
}): Promise<APNsResult> {
  const { deviceToken, eventId, env } = params;

  return sendPushNotification({
    deviceToken,
    title: 'Reminder: Are You Safe?',
    body: 'Please confirm you\'re safe. Your contacts will be notified if you don\'t respond.',
    category: 'CHECKIN_REMINDER',
    customData: {
      type: 'reminder',
      event_id: eventId,
    },
    env,
  });
}

/**
 * Send alert to contact who has the app installed
 */
export async function sendContactAlert(params: {
  deviceToken: string;
  userName: string;
  scheduledTime: string;
  env: Env;
}): Promise<APNsResult> {
  const { deviceToken, userName, scheduledTime, env } = params;

  const time = new Date(scheduledTime).toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  });

  return sendPushNotification({
    deviceToken,
    title: 'Safety Alert',
    body: `${userName} missed their ${time} check-in. Please try to contact them.`,
    category: 'CONTACT_ALERT',
    customData: {
      type: 'contact_alert',
    },
    env,
  });
}
