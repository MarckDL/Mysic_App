import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { InvalidTokenError } from '../src/modules/auth/domain/token-verifier.js';
import {
  UserConflictError,
  type UserProfile,
  type UserRepository,
} from '../src/modules/users/domain/user-repository.js';

function fixture() {
  const records = new Map<string, UserProfile>();
  const repository: UserRepository = {
    async sync(profile) {
      const now = new Date();
      const user = {
        id: randomUUID(),
        googleId: null,
        email: null,
        displayName: 'Usuario Mysic',
        photoUrl: null,
        createdAt: now,
        updatedAt: now,
        ...records.get(profile.firebaseUid),
        ...profile,
      };
      records.set(profile.firebaseUid, user);
      return user;
    },
    async findByFirebaseUid(uid) {
      return records.get(uid) ?? null;
    },
  };
  const app = createApp({
    userRepository: repository,
    tokenVerifier: {
      async verify(token) {
        if (token === 'bad') throw new InvalidTokenError();
        return {
          firebaseUid: token,
          provider: token === 'other' ? 'password' : 'google.com',
          displayName: `Usuario ${token}`,
        };
      },
    },
  });
  return { app, records, repository };
}

describe('perfiles privados', () => {
  it('crea dos perfiles distintos y conserva el UUID al repetir sync', async () => {
    const { app } = fixture();
    const a = await request(app)
      .post('/api/v1/auth/sync')
      .auth('a', { type: 'bearer' });
    const b = await request(app)
      .post('/api/v1/auth/sync')
      .auth('b', { type: 'bearer' });
    const again = await request(app)
      .post('/api/v1/auth/sync')
      .auth('a', { type: 'bearer' });
    expect([a.status, b.status, again.status]).toEqual([200, 200, 200]);
    expect(a.body.id).not.toBe(b.body.id);
    expect(again.body.id).toBe(a.body.id);
    expect(a.headers['cache-control']).toBe('no-store');
    const me = await request(app)
      .get('/api/v1/users/me')
      .auth('a', { type: 'bearer' });
    expect(me.body.id).toBe(a.body.id);
    expect(me.body.firebaseUid).toBe('a');
    expect(me.headers['cache-control']).toBe('no-store');
  });
  it.each([
    ['post', '/api/v1/auth/sync'],
    ['get', '/api/v1/users/me'],
  ] as const)('%s %s requiere autenticación y Google', async (method, path) => {
    const { app } = fixture();
    expect((await request(app)[method](path)).status).toBe(401);
    expect(
      (await request(app)[method](path).auth('bad', { type: 'bearer' })).status,
    ).toBe(401);
    expect(
      (await request(app)[method](path).auth('other', { type: 'bearer' }))
        .status,
    ).toBe(403);
  });
  it('no deja seleccionar propietarios en body o query ni enumera perfiles', async () => {
    const { app, records } = fixture();
    const body = await request(app)
      .post('/api/v1/auth/sync')
      .auth('a', { type: 'bearer' })
      .send({ firebaseUid: 'b', id: randomUUID(), googleId: 'b' });
    expect(body.status).toBe(400);
    expect(records.size).toBe(0);
    expect(
      (
        await request(app)
          .get('/api/v1/users/me?user_id=b')
          .auth('a', { type: 'bearer' })
      ).status,
    ).toBe(400);
    expect(
      (await request(app).get('/api/v1/users/b').auth('a', { type: 'bearer' }))
        .status,
    ).toBe(404);
  });
  it('indica cuándo el perfil aún no existe', async () => {
    const { app } = fixture();
    const response = await request(app)
      .get('/api/v1/users/me')
      .auth('a', { type: 'bearer' });
    expect(response.status).toBe(404);
    expect(response.body.error.code).toBe('USER_NOT_SYNCED');
  });
  it.each([
    ['sync', 'post', '/api/v1/auth/sync'],
    ['findByFirebaseUid', 'get', '/api/v1/users/me'],
  ] as const)(
    'oculta errores operativos de %s',
    async (operation, method, path) => {
      const { app, repository } = fixture();
      repository[operation] = async () => {
        throw new Error('postgres://secret:password@host');
      };
      const http = request(app);
      const response = await http[method](path).auth('a', { type: 'bearer' });
      expect(response.status).toBe(503);
      expect(response.body.error.code).toBe('DATABASE_UNAVAILABLE');
      expect(response.text).not.toContain('password');
      // Health y la comprobación de identidad siguen independientes de PostgreSQL.
      expect((await request(app).get('/api/v1/health')).status).toBe(200);
      expect(
        (
          await request(app)
            .get('/api/v1/auth/session')
            .auth('a', { type: 'bearer' })
        ).status,
      ).toBe(200);
    },
  );
  it('un conflicto no fusiona cuentas ni expone datos del propietario', async () => {
    const { app, repository } = fixture();
    repository.sync = async () => {
      throw new UserConflictError();
    };
    const response = await request(app)
      .post('/api/v1/auth/sync')
      .auth('a', { type: 'bearer' });
    expect(response.status).toBe(409);
    expect(response.body.error.code).toBe('IDENTITY_CONFLICT');
  });
});
