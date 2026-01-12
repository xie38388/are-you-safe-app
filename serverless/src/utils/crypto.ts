/**
 * Are You Safe? - Encryption Utilities
 * 
 * Uses AES-256-GCM for encrypting sensitive data (phone numbers).
 * The encryption key is stored as an environment variable.
 */

// Convert hex string to Uint8Array
function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return bytes;
}

// Convert Uint8Array to hex string
function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

// Convert string to Uint8Array
function stringToBytes(str: string): Uint8Array {
  return new TextEncoder().encode(str);
}

// Convert Uint8Array to string
function bytesToString(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

/**
 * Encrypt a string using AES-256-GCM
 * @param plaintext - The string to encrypt
 * @param keyHex - 32-byte encryption key as hex string (64 characters)
 * @returns Encrypted data as hex string (iv + ciphertext + tag)
 */
export async function encrypt(plaintext: string, keyHex: string): Promise<string> {
  // Generate random 12-byte IV
  const iv = crypto.getRandomValues(new Uint8Array(12));
  
  // Import the key
  const keyBytes = hexToBytes(keyHex);
  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'AES-GCM' },
    false,
    ['encrypt']
  );
  
  // Encrypt
  const plaintextBytes = stringToBytes(plaintext);
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    plaintextBytes
  );
  
  // Combine IV + ciphertext (includes auth tag)
  const combined = new Uint8Array(iv.length + ciphertext.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(ciphertext), iv.length);
  
  return bytesToHex(combined);
}

/**
 * Decrypt a string using AES-256-GCM
 * @param encryptedHex - Encrypted data as hex string (iv + ciphertext + tag)
 * @param keyHex - 32-byte encryption key as hex string (64 characters)
 * @returns Decrypted plaintext string
 */
export async function decrypt(encryptedHex: string, keyHex: string): Promise<string> {
  const combined = hexToBytes(encryptedHex);
  
  // Extract IV (first 12 bytes)
  const iv = combined.slice(0, 12);
  const ciphertext = combined.slice(12);
  
  // Import the key
  const keyBytes = hexToBytes(keyHex);
  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'AES-GCM' },
    false,
    ['decrypt']
  );
  
  // Decrypt
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    ciphertext
  );
  
  return bytesToString(new Uint8Array(plaintext));
}

/**
 * Generate a random UUID v4
 */
export function generateUUID(): string {
  return crypto.randomUUID();
}

/**
 * Generate a random auth token (32 bytes as hex)
 */
export function generateAuthToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return bytesToHex(bytes);
}

/**
 * Validate E.164 phone number format
 * @param phone - Phone number to validate
 * @returns true if valid E.164 format
 */
export function isValidE164(phone: string): boolean {
  // E.164 format: + followed by 1-15 digits
  return /^\+[1-9]\d{1,14}$/.test(phone);
}
