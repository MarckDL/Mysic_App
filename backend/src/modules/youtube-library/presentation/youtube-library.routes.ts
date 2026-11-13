import { Router, type RequestHandler } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type {
  AuthIdentity,
  TokenVerifier,
} from '../../auth/domain/token-verifier.js';
import type { YoutubeLibraryService } from '../application/youtube-library-service.js';
import {
  YoutubeLibraryDatabaseError,
  YoutubeLibraryQuotaError,
  YoutubeLibraryUnauthorizedError,
  YoutubeLibraryUnavailableError,
  YoutubeLibraryUserNotSyncedError,
  YoutubeRemotePlaylistNotFoundError,
} from '../domain/youtube-library.js';

const oauthToken = z.string().min(20).max(4096);
const remotePlaylistId = z.string().uuid();

function error(response: Parameters<RequestHandler>[1], value: unknown) {
  if (value instanceof z.ZodError)
    response.status(400).json({
      error: { code: 'INVALID_REQUEST', message: 'Solicitud inválida' },
    });
  else if (value instanceof YoutubeLibraryUserNotSyncedError)
    response.status(404).json({
      error: {
        code: 'USER_NOT_SYNCED',
        message: 'Sincroniza tu perfil para continuar',
      },
    });
  else if (value instanceof YoutubeRemotePlaylistNotFoundError)
    response.status(404).json({
      error: {
        code: 'YOUTUBE_PLAYLIST_NOT_FOUND',
        message: 'Playlist de YouTube no encontrada',
      },
    });
  else if (value instanceof YoutubeLibraryUnauthorizedError)
    response.status(401).json({
      error: {
        code: 'YOUTUBE_AUTH_INVALID',
        message: 'La autorización de YouTube venció o no es válida',
      },
    });
  else if (value instanceof YoutubeLibraryQuotaError)
    response.status(429).json({
      error: {
        code: 'YOUTUBE_QUOTA_EXCEEDED',
        message: 'YouTube alcanzó temporalmente su cuota',
      },
    });
  else
    response.status(503).json({
      error: {
        code:
          value instanceof YoutubeLibraryDatabaseError
            ? 'DATABASE_UNAVAILABLE'
            : 'YOUTUBE_UNAVAILABLE',
        message:
          value instanceof YoutubeLibraryUnavailableError
            ? 'YouTube no está disponible temporalmente'
            : 'No se pudo completar la operación',
      },
    });
}

function invalid(response: Parameters<RequestHandler>[1]) {
  response.status(400).json({
    error: { code: 'INVALID_REQUEST', message: 'Solicitud inválida' },
  });
}

function run(
  operation: (
    request: Parameters<RequestHandler>[0],
    identity: AuthIdentity,
  ) => Promise<unknown>,
): RequestHandler {
  return async (request, response) => {
    try {
      response
        .status(200)
        .json(await operation(request, response.locals.auth as AuthIdentity));
    } catch (value) {
      error(response, value);
    }
  };
}

export function createYoutubeLibraryRouter(
  verifier: TokenVerifier,
  service: YoutubeLibraryService,
) {
  const router = Router();
  router.use((_request, response, next) => {
    response.setHeader('Cache-Control', 'no-store');
    next();
  });
  router.use(requireAuth(verifier));

  router.get(
    '/status',
    run(async (request, identity) => {
      if (Object.keys(request.query).length || request.body !== undefined)
        throw new z.ZodError([]);
      return service.status(identity);
    }),
  );
  router.get(
    '/library',
    run(async (request, identity) => {
      if (Object.keys(request.query).length || request.body !== undefined)
        throw new z.ZodError([]);
      return service.library(identity);
    }),
  );
  router.post(
    '/sync',
    (request, response, next) => {
      if (
        Object.keys(request.query).length ||
        (request.body && Object.keys(request.body).length)
      )
        return invalid(response);
      const parsed = oauthToken.safeParse(
        request.header('x-youtube-oauth-token'),
      );
      if (!parsed.success) return invalid(response);
      response.locals.youtubeToken = parsed.data;
      next();
    },
    run((request, identity) =>
      service.sync(
        identity,
        oauthToken.parse(request.header('x-youtube-oauth-token')),
      ),
    ),
  );
  router.post(
    '/playlists/:playlistId/duplicate',
    (request, response, next) => {
      const id = remotePlaylistId.safeParse(request.params.playlistId);
      if (
        !id.success ||
        Object.keys(request.query).length ||
        (request.body && Object.keys(request.body).length)
      )
        return invalid(response);
      request.params.playlistId = id.data;
      next();
    },
    run(async (request, identity) => {
      return service.duplicate(identity, request.params.playlistId as string);
    }),
  );
  router.delete(
    '/',
    run(async (request, identity) => {
      if (Object.keys(request.query).length || request.body !== undefined)
        throw new z.ZodError([]);
      return service.disconnect(identity);
    }),
  );
  return router;
}
