import { Router, type ErrorRequestHandler } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type { TokenVerifier } from '../../auth/domain/token-verifier.js';
import { CatalogLimiter } from '../../catalog/application/catalog-limiter.js';
import { LinkError } from '../youtube/domain.js';
import { musicSurfaces } from './provider.js';
import type { YouTubeMusicService } from './service.js';

import type { ChannelMusicService } from './channel-service.js';

export const youtubeMusicRoot = '/api/v1/integrations/youtube-music';

const generation = z.uuid();
const itemId = z.string().regex(/^[A-Za-z0-9_-]{1,150}$/);
const linkBody = z
  .object({ accountId: itemId, generation: generation.nullable() })
  .strict();
const pageQuery = z
  .object({
    limit: z.coerce.number().int().min(1).max(50).optional(),
    cursor: z.string().min(1).max(4096).optional(),
    q: z.string().trim().min(1).max(120).optional(),
  })
  .strict();
const listenBody = z
  .object({
    trackId: itemId,
    listenedMs: z.number().int().min(1).max(86400000),
    activityEpoch: z.number().int().min(0).max(2147483647).optional(),
  })
  .strict();

export function youtubeMusicRouter(
  verifier: TokenVerifier,
  service: YouTubeMusicService,
  direct?: ChannelMusicService,
) {
  const router = Router();
  const limiter = new CatalogLimiter(Date.now, 90);
  router.use((_req, res, next) => {
    res.set('Cache-Control', 'private, no-store');
    next();
  });
  router.use(requireAuth(verifier));
  router.use((_req, res, next) => {
    const retry = limiter.consume(res.locals.auth.firebaseUid);
    if (retry) throw new LinkError(429, 'TOO_MANY_REQUESTS', retry);
    next();
  });
  // Explicit preview cohorts keep their isolated accounts; all other users use their own OAuth grant.
  const accountService = (uid: string) =>
    direct && !service.connection(uid).accounts.length ? direct : service;
  router.get('/connection', async (_req, res) => {
    const uid = res.locals.auth.firebaseUid;
    res.json(await accountService(uid).connection(uid));
  });
  router.post('/connection', async (req, res) => {
    const input = linkBody.parse(req.body);
    res.json(
      await service.link(
        res.locals.auth.firebaseUid,
        input.accountId,
        input.generation,
      ),
    );
  });
  router.delete('/connections/:generation', async (req, res) => {
    await accountService(res.locals.auth.firebaseUid).unlink(
      res.locals.auth.firebaseUid,
      generation.parse(req.params.generation),
    );
    res.status(204).end();
  });
  router.get(
    '/connections/:generation/pages/:surface{/:playlistId}',
    async (req, res) => {
      const surface = z.enum(musicSurfaces).parse(req.params.surface);
      const resource = itemId.optional().parse(req.params.playlistId);
      const playlistId =
        surface === 'playlist' || surface === 'album' ? resource : undefined;
      const artistId =
        surface === 'artist'
          ? z
              .string()
              .regex(/^UC[A-Za-z0-9_-]{22}$/)
              .parse(resource)
          : undefined;
      const { q, cursor, limit } = pageQuery.parse(req.query);
      if (
        (surface === 'playlist' ||
          surface === 'album' ||
          surface === 'artist') !== Boolean(resource) ||
        (surface === 'search') !== Boolean(q)
      )
        throw new LinkError(400, 'INVALID_REQUEST');
      const abort = new AbortController();
      res.on('close', () => abort.abort());
      res.json(
        await accountService(res.locals.auth.firebaseUid).read(
          res.locals.auth.firebaseUid,
          generation.parse(req.params.generation),
          { surface, playlistId, artistId, query: q },
          limit,
          cursor,
          abort.signal,
        ),
      );
    },
  );
  const activity = (uid: string) => {
    if (!direct || accountService(uid) !== direct)
      throw new LinkError(503, 'MUSIC_CAPABILITY_UNAVAILABLE');
    return direct;
  };
  router
    .route('/connections/:generation/activity')
    .put(async (req, res) => {
      const uid = res.locals.auth.firebaseUid;
      const { paused } = z
        .object({ paused: z.boolean() })
        .strict()
        .parse(req.body);
      await activity(uid).activityPreference(
        uid,
        generation.parse(req.params.generation),
        paused,
      );
      res.status(204).end();
    })
    .delete(async (req, res) => {
      const uid = res.locals.auth.firebaseUid;
      await activity(uid).activityPreference(
        uid,
        generation.parse(req.params.generation),
        'clear',
      );
      res.status(204).end();
    });
  router
    .route('/connections/:generation/listens/:id')
    .get(async (req, res) => {
      res.json({
        listen: await accountService(res.locals.auth.firebaseUid).listen(
          res.locals.auth.firebaseUid,
          generation.parse(req.params.generation),
          z.uuid().parse(req.params.id),
        ),
      });
    })
    .put(async (req, res) => {
      await accountService(res.locals.auth.firebaseUid).listen(
        res.locals.auth.firebaseUid,
        generation.parse(req.params.generation),
        z.uuid().parse(req.params.id),
        listenBody.parse(req.body),
      );
      res.status(204).end();
    });
  const handle: ErrorRequestHandler = (error, _req, res, next) => {
    if (error instanceof z.ZodError || error instanceof LinkError) {
      if (error instanceof LinkError && error.retryAfter)
        res.set('Retry-After', String(error.retryAfter));
      res.status(error instanceof LinkError ? error.status : 400).json({
        error: {
          code:
            error instanceof LinkError
              ? error.code === 'YOUTUBE_LINK_CHANGED'
                ? 'MUSIC_LINK_CHANGED'
                : error.code === 'REAUTHORIZE_YOUTUBE'
                  ? 'MUSIC_RECONNECT'
                  : error.code
              : 'INVALID_REQUEST',
          message: 'Consulta el estado del modo YouTube Music.',
        },
      });
      return;
    }
    next(error);
  };
  router.use(handle);
  return router;
}
