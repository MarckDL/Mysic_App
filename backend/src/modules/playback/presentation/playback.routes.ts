import { Router } from 'express';
import type {
  TokenVerifier,
  AuthIdentity,
} from '../../auth/domain/token-verifier.js';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import { CatalogLimiter } from '../../catalog/application/catalog-limiter.js';
import { ProviderTimeoutError } from '../../catalog/domain/music-provider.js';
import type { PlaybackService } from '../application/playback-service.js';

export function createPlaybackRouter(
  verifier: TokenVerifier,
  service: PlaybackService,
) {
  const router = Router();
  const limiter = new CatalogLimiter();
  router.use((_request, response, next) => {
    response.setHeader('Cache-Control', 'no-store');
    next();
  });
  router.post('/resolve', requireAuth(verifier), async (request, response) => {
    const wait = limiter.consume(
      (response.locals.auth as AuthIdentity).firebaseUid,
    );
    if (wait !== null) {
      response.setHeader('Retry-After', wait);
      response.status(429).json({
        error: {
          code: 'PLAYBACK_RATE_LIMITED',
          message: 'Espera antes de intentarlo de nuevo',
        },
      });
      return;
    }
    const body = request.body as unknown;
    if (
      !body ||
      typeof body !== 'object' ||
      Array.isArray(body) ||
      Object.keys(request.query).length ||
      Object.keys(body).length !== 2 ||
      !('source' in body) ||
      !('sourceId' in body) ||
      typeof body.sourceId !== 'string' ||
      !(
        (body.source === 'youtube' &&
          /^[A-Za-z0-9_-]{11}$/.test(body.sourceId)) ||
        (body.source === 'demo' && /^[a-z0-9-]{1,64}$/.test(body.sourceId))
      )
    ) {
      response.status(400).json({
        error: {
          code: 'INVALID_REQUEST',
          message: 'Fuente de reproducción inválida',
        },
      });
      return;
    }
    try {
      response.json(
        await service.resolve(body.source as string, body.sourceId),
      );
    } catch (error) {
      const timeout = error instanceof ProviderTimeoutError;
      response.status(timeout ? 504 : 503).json({
        error: {
          code: timeout ? 'PLAYBACK_TIMEOUT' : 'PLAYBACK_UNAVAILABLE',
          message: 'No se pudo comprobar la reproducción. Inténtalo de nuevo',
        },
      });
    }
  });
  return router;
}
