import { Router, type RequestHandler } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type {
  AuthIdentity,
  TokenVerifier,
} from '../../auth/domain/token-verifier.js';
import { ProviderTimeoutError } from '../../catalog/domain/music-provider.js';
import type { FavoriteService } from '../../favorites/application/favorite-service.js';
import {
  FavoriteDatabaseError,
  FavoriteUserNotSyncedError,
} from '../../favorites/domain/favorite.js';
import type { RatingService } from '../application/rating-service.js';
import {
  RatingDatabaseError,
  RatingTrackNotFoundError,
  RatingUserNotSyncedError,
} from '../domain/rating.js';

const trackId = z.string().regex(/^youtube:[A-Za-z0-9_-]{11}$/);
const ratingBody = z.object({ score: z.number().int().min(1).max(5) }).strict();

function sendError(response: Parameters<RequestHandler>[1], error: unknown) {
  if (error instanceof z.ZodError) {
    response.status(400).json({
      error: { code: 'INVALID_REQUEST', message: 'Solicitud inválida' },
    });
  } else if (
    error instanceof RatingUserNotSyncedError ||
    error instanceof FavoriteUserNotSyncedError
  ) {
    response.status(404).json({
      error: {
        code: 'USER_NOT_SYNCED',
        message: 'Sincroniza tu perfil para continuar',
      },
    });
  } else if (error instanceof RatingTrackNotFoundError) {
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
          error instanceof RatingDatabaseError ||
          error instanceof FavoriteDatabaseError
            ? 'DATABASE_UNAVAILABLE'
            : 'CATALOG_UNAVAILABLE',
        message: 'No se pudo completar la operación',
      },
    });
  }
}

export function createRatingRouter(
  verifier: TokenVerifier,
  ratings: RatingService,
) {
  const router = Router();
  router.use((_request, response, next) => {
    response.setHeader('Cache-Control', 'no-store');
    next();
  });
  router.use(requireAuth(verifier));
  router.put('/:catalogTrackId', async (request, response) => {
    try {
      const id = trackId.safeParse(request.params.catalogTrackId);
      const body = ratingBody.safeParse(request.body);
      if (!id.success || !body.success || Object.keys(request.query).length)
        throw new z.ZodError([]);
      response.json(
        await ratings.rate(
          response.locals.auth as AuthIdentity,
          id.data,
          body.data.score,
        ),
      );
    } catch (error) {
      sendError(response, error);
    }
  });
  return router;
}

export function createInteractionRouter(
  verifier: TokenVerifier,
  favorites: FavoriteService,
  ratings: RatingService,
) {
  const router = Router();
  router.use((_request, response, next) => {
    response.setHeader('Cache-Control', 'no-store');
    next();
  });
  router.use(requireAuth(verifier));
  router.get('/:catalogTrackId/interactions', async (request, response) => {
    try {
      const id = trackId.safeParse(request.params.catalogTrackId);
      if (
        !id.success ||
        Object.keys(request.query).length ||
        request.body !== undefined
      )
        throw new z.ZodError([]);
      const identity = response.locals.auth as AuthIdentity;
      const [isFavorite, rating] = await Promise.all([
        favorites.status(identity, id.data),
        ratings.status(identity, id.data),
      ]);
      response.json({ isFavorite, ...rating });
    } catch (error) {
      sendError(response, error);
    }
  });
  return router;
}
