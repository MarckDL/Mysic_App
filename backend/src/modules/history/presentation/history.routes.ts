import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type {
  AuthIdentity,
  TokenVerifier,
} from '../../auth/domain/token-verifier.js';
import type { HistoryService } from '../application/history-service.js';
import { HistoryConflict, HistoryInvalid } from '../domain/history.js';
const cursorSchema = z
  .object({ startedAt: z.iso.datetime(), id: z.uuid() })
  .strict();
const body = z
  .object({
    catalogTrackId: z.string().regex(/^youtube:[A-Za-z0-9_-]{11}$/),
    startedAt: z.iso.datetime(),
    listenedMs: z.number().int().min(1).max(86400000),
    completed: z.boolean(),
  })
  .strict();
export function createHistoryRouter(
  verifier: TokenVerifier,
  service: HistoryService,
) {
  const router = Router();
  router.use(requireAuth(verifier));
  router.use((_req, res, next) => {
    res.setHeader('Cache-Control', 'no-store');
    next();
  });
  router.put('/:sessionId', async (req, res) => {
    try {
      const sessionId = z.uuid().parse(req.params.sessionId);
      if (Object.keys(req.query).length) throw new HistoryInvalid();
      await service.save((res.locals.auth as AuthIdentity).firebaseUid, {
        ...body.parse(req.body),
        sessionId,
      });
      res.status(204).end();
    } catch (e) {
      fail(res, e);
    }
  });
  router.get('/', async (req, res) => {
    try {
      const q = z
        .object({
          limit: z.coerce.number().int().min(1).max(50).default(20),
          cursor: z.string().max(512).optional(),
        })
        .strict()
        .parse(req.query);
      let cursor;
      if (q.cursor) {
        try {
          cursor = cursorSchema.parse(
            JSON.parse(Buffer.from(q.cursor, 'base64url').toString()),
          );
        } catch {
          throw new HistoryInvalid();
        }
      }
      res.json(
        await service.list(
          (res.locals.auth as AuthIdentity).firebaseUid,
          q.limit,
          cursor,
        ),
      );
    } catch (e) {
      fail(res, e);
    }
  });
  return router;
}
function fail(res: import('express').Response, e: unknown) {
  const status =
    e instanceof HistoryConflict
      ? 409
      : e instanceof HistoryInvalid || e instanceof z.ZodError
        ? 400
        : 503;
  res.status(status).json({
    error: {
      code:
        status === 409
          ? 'HISTORY_CONFLICT'
          : status === 400
            ? 'INVALID_REQUEST'
            : 'HISTORY_UNAVAILABLE',
      message: 'No se pudo completar la operación de historial',
    },
  });
}
