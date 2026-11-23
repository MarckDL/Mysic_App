import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createBootstrapRouter } from '../src/modules/bootstrap/presentation/bootstrap.routes.js';

describe('GET /api/v2/bootstrap', () => {
  it('verifica una vez y devuelve perfil, conexión e Inicio', async () => {
    const verify = vi.fn(async () => ({
      firebaseUid: 'firebase-a',
      provider: 'google.com',
    }));
    const sync = vi.fn(async () => ({ id: 'user-a', displayName: 'Mysic' }));
    const rememberOwner = vi.fn();
    const connection = vi.fn(async () => ({
      status: 'linked',
      generation: '11111111-1111-4111-8111-111111111111',
    }));
    const read = vi.fn(async () => ({
      items: [{ kind: 'track', id: 'abcdefghijk' }],
      nextCursor: null,
      excludedCount: 0,
    }));
    const app = express();
    app.use(
      '/api/v2/bootstrap',
      createBootstrapRouter(
        { verify },
        { sync } as never,
        { rememberOwner } as never,
        { connection, read } as never,
      ),
    );

    const response = await request(app)
      .get('/api/v2/bootstrap')
      .auth('token', { type: 'bearer' });

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({
      profile: { id: 'user-a' },
      connection: { status: 'linked' },
      home: { items: [{ id: 'abcdefghijk' }] },
    });
    expect(verify).toHaveBeenCalledTimes(1);
    expect(sync).toHaveBeenCalledTimes(1);
    expect(rememberOwner).toHaveBeenCalledWith('firebase-a', 'user-a');
    expect(connection).toHaveBeenCalledTimes(1);
    expect(read).toHaveBeenCalledTimes(1);
  });
});
