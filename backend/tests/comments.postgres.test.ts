import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import {
  disconnectDatabase,
  getDatabase,
} from '../src/infrastructure/database/prisma.js';
import { InvalidTokenError } from '../src/modules/auth/domain/token-verifier.js';

describe.skipIf(!process.env.TEST_DATABASE_URL)(
  'comentarios HTTP con PostgreSQL real',
  () => {
    const sourceId = randomUUID().replaceAll('-', '').slice(0, 11);
    const prefix = `comments-test-${sourceId}`;
    const trackId = `youtube:${sourceId}`;
    const trackPath = `/api/v1/tracks/${trackId}/comments`;
    const moderationPath = '/api/v1/moderation/comments';
    const commentPath = (id: string) => `/api/v1/comments/${id}`;
    const reportPath = (id: string) => `${commentPath(id)}/reports`;
    const bearer = { type: 'bearer' } as const;
    const revoked = new Set<string>();
    const app = request(
      createApp({
        tokenVerifier: {
          async verify(token) {
            if (token === 'invalid' || revoked.has(token))
              throw new InvalidTokenError();
            return {
              firebaseUid: `${prefix}-${token}`,
              provider: token === 'password' ? 'password' : 'google.com',
              moderator: token === 'moderator' || token === 'moderator-2',
            };
          },
        },
        musicProvider: {
          async search() {
            return [];
          },
          async getTrack(id) {
            if (id !== sourceId) return null;
            return {
              id: trackId,
              source: 'youtube',
              sourceId,
              title: 'Canción de prueba',
              artistName: 'Mysic Test',
              durationSeconds: 60,
              thumbnailUrl: null,
            };
          },
          async resolvePlayback() {
            throw new Error('No se usa en los comentarios');
          },
        },
      }),
    );
    const create = (body: string) =>
      app.post(trackPath).auth('a', bearer).send({ body }).expect(201);
    const list = (account: string) => app.get(trackPath).auth(account, bearer);
    const report = (id: string, reason: string, reporter = 'b') =>
      app.post(reportPath(id)).auth(reporter, bearer).send({ reason });
    const resolve = (id: string, action: string, moderator = 'moderator') =>
      app
        .patch(`${moderationPath}/${id}`)
        .auth(moderator, bearer)
        .send({ action });

    beforeAll(async () => {
      process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
      await getDatabase().user.createMany({
        data: ['a', 'b', 'moderator', 'moderator-2'].map((account) => ({
          firebaseUid: `${prefix}-${account}`,
          displayName: `Cuenta ${account}`,
          email: `${account}@example.test`,
        })),
      });
    });

    afterAll(async () => {
      try {
        await getDatabase().user.deleteMany({
          where: { firebaseUid: { startsWith: prefix } },
        });
        await getDatabase().track.deleteMany({
          where: { source: 'youtube', sourceId },
        });
      } finally {
        await disconnectDatabase();
      }
    });

    it('exige token Google y perfil y valida el contrato de entrada', async () => {
      await app.get(trackPath).expect(401).expect('Cache-Control', 'no-store');
      await list('invalid').expect(401);
      await list('password').expect(403);
      await list('missing')
        .expect(404)
        .expect(({ body }) => {
          expect(body.error.code).toBe('USER_NOT_SYNCED');
        });
      for (const body of ['   ', 'a'.repeat(501), 'a\0b', '\uD800']) {
        await app.post(trackPath).auth('a', bearer).send({ body }).expect(400);
      }
      await app
        .post(trackPath)
        .auth('a', bearer)
        .send({ body: 'válido', user_id: 'b' })
        .expect(400);
      await app
        .post('/api/v1/tracks/youtube:___________/comments')
        .auth('a', bearer)
        .send({ body: 'válido' })
        .expect(404);
      await list('a').query({ cursor: 'bad' }).expect(400);
      await list('a').query({ limit: 51 }).expect(400);
      await app
        .get('/api/v1/users/me')
        .auth('moderator', bearer)
        .expect(({ body }) => {
          expect(body.canModerateComments).toBe(true);
        });
      await app
        .get('/api/v1/users/me')
        .auth('a', bearer)
        .expect(({ body }) => {
          expect(body.canModerateComments).toBe(false);
        });
    });

    it('aísla edición y baja y pagina con empate de fecha y cursor eliminado', async () => {
      const first = (await create('   Primer comentario 😀   ')).body;
      const second = (await create('Segundo comentario')).body;
      const third = (await create('Tercer comentario')).body;
      await getDatabase().comment.updateMany({
        where: { id: { in: [first.id, second.id, third.id] } },
        data: { createdAt: new Date('2026-11-15T00:00:00.123Z') },
      });
      expect(first).toMatchObject({
        body: 'Primer comentario 😀',
        authorName: 'Cuenta a',
        isMine: true,
      });
      await app
        .patch(commentPath(first.id))
        .auth('a', bearer)
        .send({ body: '<b>Texto plano</b>' })
        .expect(200);
      await app
        .patch(commentPath(first.id))
        .auth('b', bearer)
        .send({ body: 'Ajeno' })
        .expect(403);
      await app.delete(commentPath(first.id)).auth('b', bearer).expect(403);
      await report(first.id, 'spam', 'a').expect(403);
      const { body: initial } = await list('b').query({ limit: 1 }).expect(200);
      expect(initial.items[0]).toMatchObject({
        isMine: false,
        authorName: 'Cuenta a',
      });
      expect(Object.keys(initial.items[0]).sort()).toEqual([
        'authorName',
        'body',
        'createdAt',
        'id',
        'isMine',
        'updatedAt',
      ]);
      await app
        .delete(commentPath(initial.items[0].id))
        .auth('a', bearer)
        .expect(204);
      const { body: next } = await list('b')
        .query({ limit: 2, cursor: initial.nextCursor })
        .expect(200);
      expect(next.items.map((item: { id: string }) => item.id)).toEqual(
        [first.id, second.id, third.id].sort().reverse().slice(1),
      );
      expect(next.nextCursor).toBeNull();
    });

    it('deduplica reportes y una sola sesión puede resolver la misma entrada', async () => {
      const {
        body: { id },
      } = await create('Comentario moderado');
      await report(id, 'unknown').expect(400);
      await Promise.all(
        Array.from({ length: 4 }, () => report(id, 'spam').expect(204)),
      );
      await report(id, 'harassment', 'moderator-2').expect(204);
      expect(
        await getDatabase().commentReport.count({ where: { commentId: id } }),
      ).toBe(2);
      await app.get(moderationPath).auth('b', bearer).expect(403);
      await resolve(id, 'hide', 'b').expect(403);
      const { body: queue } = await app
        .get(moderationPath)
        .auth('moderator', bearer)
        .expect(200);
      expect(queue.items).toContainEqual(
        expect.objectContaining({
          id,
          body: 'Comentario moderado',
          reasons: ['harassment', 'spam'],
        }),
      );
      const results = await Promise.all([
        resolve(id, 'hide'),
        resolve(id, 'hide', 'moderator-2'),
      ]);
      expect(results.map((result) => result.status).sort()).toEqual([204, 409]);
      await list('b').expect(({ body }) => {
        expect(body.items).not.toContainEqual(expect.objectContaining({ id }));
      });
      await report(id, 'spam', 'moderator').expect(404);
      await report(id, 'other').expect(204);
      expect(
        await getDatabase().commentReport.count({
          where: { commentId: id, status: 'hidden' },
        }),
      ).toBe(2);
    });

    it('pagina la cola, desestima, cierra reportes al eliminar y rechaza el token revocado', async () => {
      const first = (await create('Se conserva')).body.id as string;
      const second = (await create('Se elimina')).body.id as string;
      await report(first, 'other').expect(204);
      await report(second, 'spam').expect(204);
      await getDatabase().commentReport.updateMany({
        where: { commentId: first },
        data: { createdAt: new Date('2026-11-15T00:00:00.123Z') },
      });
      await getDatabase().commentReport.updateMany({
        where: { commentId: second },
        data: { createdAt: new Date('2026-11-15T00:00:00.124Z') },
      });
      const { body: firstPage } = await app
        .get(moderationPath)
        .auth('moderator', bearer)
        .query({ limit: 1 })
        .expect(200);
      expect(firstPage.items[0].id).toBe(first);
      await resolve(first, 'dismiss').expect(204);
      const { body: secondPage } = await app
        .get(moderationPath)
        .auth('moderator', bearer)
        .query({ limit: 1, cursor: firstPage.nextCursor })
        .expect(200);
      expect(secondPage.items[0].id).toBe(second);
      expect(secondPage.nextCursor).toBeNull();
      await list('b').expect(({ body }) => {
        expect(body.items).toContainEqual(
          expect.objectContaining({ id: first }),
        );
      });
      await Promise.all([
        app.delete(commentPath(second)).auth('a', bearer).expect(204),
        report(second, 'other', 'moderator-2').then((result) =>
          expect([204, 404]).toContain(result.status),
        ),
      ]);
      expect(
        await getDatabase().commentReport.count({
          where: { commentId: second, status: 'pending' },
        }),
      ).toBe(0);
      await resolve(second, 'hide').expect(409);
      revoked.add('moderator');
      await app.get(moderationPath).auth('moderator', bearer).expect(401);
    });

    it('habilita RLS y exige texto válido también en la base', async () => {
      const {
        body: { id },
      } = await create('Comentario válido');
      await expect(
        getDatabase().comment.update({ where: { id }, data: { body: '   ' } }),
      ).rejects.toThrow();
      const rows = await getDatabase().$queryRaw<{ relrowsecurity: boolean }[]>`
      SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'mysic' AND c.relname IN ('comments', 'comment_reports')
    `;
      expect(rows).toEqual([
        { relrowsecurity: true },
        { relrowsecurity: true },
      ]);
    });
  },
);
