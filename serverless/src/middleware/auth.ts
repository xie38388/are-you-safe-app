/**
 * Are You Safe? - Authentication Middleware
 * 
 * Validates auth tokens and attaches user info to context.
 */

import { Context, Next } from 'hono';
import { Env, User } from '../types';

// Extended context with user info
export interface AuthContext {
  user: User;
}

/**
 * Authentication middleware
 * Validates the Authorization header and attaches user to context
 */
export async function authMiddleware(
  c: Context<{ Bindings: Env; Variables: AuthContext }>,
  next: Next
) {
  const authHeader = c.req.header('Authorization');
  
  if (!authHeader) {
    return c.json({ error: 'Missing Authorization header' }, 401);
  }
  
  // Extract token from "Bearer <token>" format
  const parts = authHeader.split(' ');
  if (parts.length !== 2 || parts[0] !== 'Bearer') {
    return c.json({ error: 'Invalid Authorization header format' }, 401);
  }
  
  const token = parts[1];
  
  // Look up user by auth token
  const user = await c.env.DB.prepare(
    'SELECT * FROM users WHERE auth_token = ?'
  ).bind(token).first<User>();
  
  if (!user) {
    return c.json({ error: 'Invalid or expired token' }, 401);
  }
  
  // Attach user to context
  c.set('user', user);
  
  await next();
}

/**
 * Optional auth middleware - doesn't fail if no token provided
 * Useful for endpoints that work differently for authenticated users
 */
export async function optionalAuthMiddleware(
  c: Context<{ Bindings: Env; Variables: Partial<AuthContext> }>,
  next: Next
) {
  const authHeader = c.req.header('Authorization');
  
  if (authHeader) {
    const parts = authHeader.split(' ');
    if (parts.length === 2 && parts[0] === 'Bearer') {
      const token = parts[1];
      const user = await c.env.DB.prepare(
        'SELECT * FROM users WHERE auth_token = ?'
      ).bind(token).first<User>();
      
      if (user) {
        c.set('user', user);
      }
    }
  }
  
  await next();
}
