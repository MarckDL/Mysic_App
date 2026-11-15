import express from 'express';
import { IncomingMessage, ServerResponse } from 'node:http';
import { Socket } from 'node:net';
import { describe, it, expect, vi } from 'vitest';
import { createHistoryRouter } from '../src/modules/history/presentation/history.routes.js';
import { HistoryService } from '../src/modules/history/application/history-service.js';
import {
  HistoryConflict,
  type HistoryRepository,
} from '../src/modules/history/domain/history.js';
import { InvalidTokenError } from '../src/modules/auth/domain/token-verifier.js';
import type { CatalogService } from '../src/modules/catalog/application/catalog-service.js';

// Exercise Express routing and authorization in process; no listening socket.
function setup() {
  const repository: HistoryRepository = {
    owner: vi.fn(async () => 'owner-a'),
    save: vi.fn(async () => {}),
    list: vi.fn(async () => []),
  };
  const service = new HistoryService(repository, {
    getTrack: async () => ({
      id: 'youtube:abcdefghijk',
      source: 'youtube',
      sourceId: 'abcdefghijk',
      title: 'Song',
      artistName: 'Artist',
      durationSeconds: 120,
      thumbnailUrl: null,
    }),
  } as unknown as CatalogService);
  const app = express();
  app.use(
    '/api/v1/history',
    createHistoryRouter(
      {
        verify: async (token) => {
          if (token !== 'valid') throw new InvalidTokenError();
          return { firebaseUid: 'account-a', provider: 'google.com' };
        },
      },
      service,
    ),
  );
  const request = (
    method: string,
    url: string,
    body?: unknown,
    token: string | null = 'valid',
  ) =>
    new Promise<{
      status: number;
      body: Record<string, unknown>;
      cache: unknown;
    }>((resolve, reject) => {
      const socket = new Socket();
      const req = new IncomingMessage(socket);
      req.method = method;
      req.url = url;
      if (token) req.headers.authorization = `Bearer ${token}`;
      Object.assign(req, { body });
      const res = new ServerResponse(req);
      Object.defineProperty(res, 'end', {
        value: (chunk?: string | Buffer) => {
          resolve({
            status: res.statusCode,
            body: chunk ? JSON.parse(chunk.toString()) : {},
            cache: res.getHeader('Cache-Control'),
          });
          socket.destroy();
          return res;
        },
      });
      app(
        req as express.Request,
        res as express.Response,
        (error?: unknown) => {
          socket.destroy();
          reject(error ?? new Error('Unhandled route'));
        },
      );
    });
  return { repository, request };
}
const input = () => ({
  catalogTrackId: 'youtube:abcdefghijk',
  startedAt: new Date(Date.now() - 60000).toISOString(),
  listenedMs: 30000,
  completed: false,
});
const session = 'f406a218-04d7-45d4-8674-acd884361385';
describe('history Express contract in process', () => {
  it.each([null, 'bad'])(
    'rejects missing/invalid identity: %s',
    async (token) => {
      const { request, repository } = setup();
      expect(
        (await request('GET', '/api/v1/history', undefined, token)).status,
      ).toBe(401);
      expect(repository.list).not.toHaveBeenCalled();
    },
  );
  it('derives ownership from verified Firebase identity', async () => {
    const { request, repository } = setup();
    const result = await request('PUT', `/api/v1/history/${session}`, input());
    expect(result.status).toBe(204);
    expect(repository.owner).toHaveBeenCalledWith('account-a');
    expect(repository.save).toHaveBeenCalledWith(
      'owner-a',
      expect.objectContaining({ sessionId: session }),
      expect.anything(),
    );
  });
  it('rejects injected user ids and malformed cursors', async () => {
    const { request, repository } = setup();
    expect(
      (
        await request('PUT', `/api/v1/history/${session}`, {
          ...input(),
          userId: 'other',
        })
      ).status,
    ).toBe(400);
    expect(
      (await request('GET', '/api/v1/history?cursor=malformed')).status,
    ).toBe(400);
    expect(repository.save).not.toHaveBeenCalled();
  });
  it('returns conflicts without disclosing another owner', async () => {
    const { request, repository } = setup();
    vi.mocked(repository.save).mockRejectedValue(new HistoryConflict());
    const result = await request('PUT', `/api/v1/history/${session}`, input());
    expect(result.status).toBe(409);
    expect(result.body).toEqual({
      error: {
        code: 'HISTORY_CONFLICT',
        message: 'No se pudo completar la operación de historial',
      },
    });
  });
  it('paginates and prevents caching of private responses', async () => {
    const { request } = setup();
    const result = await request('GET', '/api/v1/history?limit=1');
    expect(result.status).toBe(200);
    expect(result.cache).toBe('no-store');
    expect(result.body).toEqual({ items: [], nextCursor: null });
  });
});
