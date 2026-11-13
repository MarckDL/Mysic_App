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
  FavoriteTrackNotFoundError,
  FavoriteUserNotSyncedError,
} from '../domain/favorite.js';

const trackId = z.string().regex(/^youtube:[A-Za-z0-9_-]{11}$/);
const emptyBody = z.object({}).strict();

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
  } else if (error instanceof FavoriteTrackNotFoundError) {
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

  router.get('/', async (request, response) => {
    try {
      if (Object.keys(request.query).length || request.body !== undefined)
        throw new z.ZodError([]);
      response.json({
        items: await service.list(response.locals.auth as AuthIdentity),
      });
    } catch (error) {
      sendError(response, error);
    }
  });

  router.put('/:catalogTrackId', async (request, response) => {
    try {
      const id = trackId.safeParse(request.params.catalogTrackId);
      const body = emptyBody.safeParse(request.body);
      if (
        !id.success ||
        !body.success ||
        Object.keys(request.query).length ||
        request.body === undefined
      )
        throw new z.ZodError([]);
      await service.add(response.locals.auth as AuthIdentity, id.data);
      response.json({ isFavorite: true });
    } catch (error) {
      sendError(response, error);
    }
  });

  router.delete('/:catalogTrackId', async (request, response) => {
    try {
      const id = trackId.safeParse(request.params.catalogTrackId);
      if (
        !id.success ||
        Object.keys(request.query).length ||
        request.body !== undefined
      )
        throw new z.ZodError([]);
      await service.remove(response.locals.auth as AuthIdentity, id.data);
      response.json({ isFavorite: false });
    } catch (error) {
      sendError(response, error);
    }
  });
  return router;
}
