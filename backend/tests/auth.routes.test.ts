import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { InvalidTokenError } from '../src/modules/auth/domain/token-verifier.js';

describe('GET /api/v1/auth/session', () => {
  it('rechaza solicitudes sin token', async () => {
    const response = await request(createApp()).get('/api/v1/auth/session');
    expect(response.status).toBe(401);
    expect(response.headers['cache-control']).toBe('no-store');
  });
  it('rechaza tokens inválidos', async () => {
    const app = createApp({
      tokenVerifier: {
        verify: async () => {
          throw new InvalidTokenError();
        },
      },
    });
    const response = await request(app)
      .get('/api/v1/auth/session')
      .auth('invalid', { type: 'bearer' });
    expect(response.status).toBe(401);
  });
  it('responde con identidad verificada sin perfiles ficticios', async () => {
    const app = createApp({
      tokenVerifier: {
        verify: async () => ({ firebaseUid: 'a', provider: 'google.com' }),
      },
    });
    const response = await request(app)
      .get('/api/v1/auth/session?user_id=b')
      .auth('token', { type: 'bearer' });
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ firebaseUid: 'a', provider: 'google.com' });
    expect(response.body.id).toBeUndefined();
  });
});
