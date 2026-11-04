import { Router } from 'express';
import { pipeline } from 'node:stream/promises';
import type {
  TokenVerifier,
  AuthIdentity,
} from '../../auth/domain/token-verifier.js';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type { AudioStreamTransport } from '../../../infrastructure/music/youtube-audio-stream.js';
import { CatalogLimiter } from '../../catalog/application/catalog-limiter.js';

export function createAudioStreamRouter(
  verifier: TokenVerifier,
  transport: AudioStreamTransport,
) {
  const router = Router();
  const active = new Set<string>();
  const limiter = new CatalogLimiter();
  router.get(
    '/audio/:sourceId',
    requireAuth(verifier),
    async (request, response) => {
      response.setHeader('Cache-Control', 'no-store');
      response.setHeader('X-Content-Type-Options', 'nosniff');
      const uid = (response.locals.auth as AuthIdentity).firebaseUid;
      const sourceId = request.params.sourceId;
      if (request.method === 'HEAD') {
        response.setHeader('Allow', 'GET');
        response.status(405).end();
        return;
      }
      if (
        typeof sourceId !== 'string' ||
        !/^[A-Za-z0-9_-]{11}$/.test(sourceId) ||
        Object.keys(request.query).length
      ) {
        response.status(400).json({
          error: { code: 'INVALID_REQUEST', message: 'Pista inválida' },
        });
        return;
      }
      const wait = limiter.consume(uid);
      if (wait !== null || active.has(uid) || active.size >= 2) {
        response.setHeader('Retry-After', wait ?? 2);
        response.status(429).json({
          error: {
            code: 'PLAYBACK_BUSY',
            message: 'Detén el audio anterior e inténtalo de nuevo',
          },
        });
        return;
      }
      if (request.headers.range && request.headers.range !== 'bytes=0-') {
        response.status(416).end();
        return;
      }
      active.add(uid);
      const controller = new AbortController();
      const cancel = () => controller.abort();
      response.once('close', cancel);
      try {
        const audio = await transport.open(sourceId, controller.signal);
        if (controller.signal.aborted) {
          audio.destroy();
          return;
        }
        response.status(200);
        response.setHeader('Content-Type', 'audio/mp4');
        response.setHeader('Accept-Ranges', 'none');
        await pipeline(audio, response, { signal: controller.signal });
      } catch {
        if (!response.headersSent && !response.destroyed) {
          response.status(503).json({
            error: {
              code: 'PLAYBACK_UNAVAILABLE',
              message: 'No se pudo abrir el audio de esta pista',
            },
          });
        } else if (!response.destroyed) response.destroy();
      } finally {
        cancel();
        active.delete(uid);
        response.off('close', cancel);
      }
    },
  );
  return router;
}
