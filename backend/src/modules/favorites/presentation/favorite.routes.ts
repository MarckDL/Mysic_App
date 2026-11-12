import { Router, type RequestHandler } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type {
  AuthIdentity,
  TokenVerifier,
} from '../../auth/domain/token-verifier.js';
import { ProviderTimeoutError } from '../../catalog/domain/music-provider.js';
import type { FavoriteService } from '../application/favorite-service.js';
import {
  FavoriteDatabaseError,
  FavoriteTrackUnavailableError,
  FavoriteUserNotSyncedError,
} from '../domain/favorite.js';

const trackParams = z.object({
  source: z.literal('youtube'),
  sourceId: z.string().regex(/^[A-Za-z0-9_-]{11}$/),
});

function sendError(response: Parameters<RequestHandler>[1], error: unknown) {
  if (error instanceof z.ZodError) {
    response.status(400).json({
      error: { code: 'INVALID_REQUEST', message: 'Solicitud inválida' },
    });
  } else if (error instanceof FavoriteUserNotSyncedError) {
    response.status(404).json({
      error: {
        code: 'USER_NOT_SYNCED',
        message: 'Sincroniza tu perfil para continuar',
      },
    });
  } else if (error instanceof FavoriteTrackUnavailableError) {
    response.status(404).json({
      error: { code: 'TRACK_NOT_FOUND', message: 'Pista no encontrada' },
    });
  } else if (error instanceof ProviderTimeoutError) {
    response.status(504).json({
      error: {
        code: 'CATALOG_TIMEOUT',
        message: 'El catálogo tardó demasiado en responder',
      },
    });
  } else {
    response.status(503).json({
      error: {
        code:
          error instanceof FavoriteDatabaseError
            ? 'DATABASE_UNAVAILABLE'
            : 'CATALOG_UNAVAILABLE',
        message: 'No se pudo completar la operación',
      },
    });
  }
}

function handler(
  operation: (
    request: Parameters<RequestHandler>[0],
    identity: AuthIdentity,
  ) => Promise<unknown>,
): RequestHandler {
  return async (request, response) => {
    try {
      response.json(
        await operation(request, response.locals.auth as AuthIdentity),
      );
    } catch (error) {
      sendError(response, error);
    }
  };
}

function parseTrack(request: Parameters<RequestHandler>[0]) {
  if (Object.keys(request.query).length || request.body !== undefined)
    throw new z.ZodError([]);
  return trackParams.parse(request.params);
}

export function createFavoriteRouter(
  verifier: TokenVerifier,
  service: FavoriteService,
) {
  const router = Router();
  router.use((_request, response, next) => {
    response.setHeader('Cache-Control', 'no-store');
    next();
  });
  router.use(requireAuth(verifier));

  router.get(
    '/',
    handler(async (request, identity) => {
      if (Object.keys(request.query).length || request.body !== undefined)
        throw new z.ZodError([]);
      return { items: await service.list(identity) };
    }),
  );
  router.get(
    '/:source/:sourceId',
    handler((request, identity) => {
      const value = parseTrack(request);
      return service.status(identity, value.source, value.sourceId);
    }),
  );
  router.put(
    '/:source/:sourceId',
    handler((request, identity) => {
      const value = parseTrack(request);
      return service.add(identity, value.source, value.sourceId);
    }),
  );
  router.delete(
    '/:source/:sourceId',
    handler((request, identity) => {
      const value = parseTrack(request);
      return service.remove(identity, value.source, value.sourceId);
    }),
  );
  return router;
}
