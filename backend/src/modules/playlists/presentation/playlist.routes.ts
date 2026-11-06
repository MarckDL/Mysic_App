import { Router, type RequestHandler } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type {
  AuthIdentity,
  TokenVerifier,
} from '../../auth/domain/token-verifier.js';
import { ProviderTimeoutError } from '../../catalog/domain/music-provider.js';
import type { PlaylistService } from '../application/playlist-service.js';
import {
  PlaylistCapacityError,
  PlaylistConflictError,
  PlaylistDatabaseError,
  PlaylistInvalidOrderError,
  PlaylistNotFoundError,
  PlaylistTrackUnavailableError,
  UserNotSyncedError,
} from '../domain/playlist.js';

const playlistId = z.string().uuid();
const text = z.string().trim();
const createBody = z
  .object({
    name: text.min(1).max(150),
    description: text.max(2000).nullable().optional().default(null),
    visibility: z.enum(['private', 'public']).optional().default('private'),
  })
  .strict();
const updateBody = z
  .object({
    name: text.min(1).max(150).optional(),
    description: text.max(2000).nullable().optional(),
    visibility: z.enum(['private', 'public']).optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0);
const addBody = z
  .object({ catalogTrackId: z.string().regex(/^youtube:[A-Za-z0-9_-]{11}$/) })
  .strict();
const orderBody = z
  .object({ itemIds: z.array(z.string().uuid()).max(500) })
  .strict();

function sendError(response: Parameters<RequestHandler>[1], error: unknown) {
  if (error instanceof z.ZodError) {
    response.status(400).json({
      error: { code: 'INVALID_REQUEST', message: 'Solicitud inválida' },
    });
  } else if (error instanceof UserNotSyncedError) {
    response.status(404).json({
      error: {
        code: 'USER_NOT_SYNCED',
        message: 'Sincroniza tu perfil para continuar',
      },
    });
  } else if (error instanceof PlaylistTrackUnavailableError) {
    response.status(404).json({
      error: { code: 'TRACK_NOT_FOUND', message: 'Pista no encontrada' },
    });
  } else if (error instanceof PlaylistNotFoundError) {
    response.status(404).json({
      error: { code: 'PLAYLIST_NOT_FOUND', message: 'Playlist no encontrada' },
    });
  } else if (error instanceof PlaylistInvalidOrderError) {
    response.status(400).json({
      error: { code: 'INVALID_ORDER', message: 'Orden de canciones inválido' },
    });
  } else if (error instanceof PlaylistCapacityError) {
    response.status(409).json({
      error: {
        code: 'PLAYLIST_FULL',
        message: 'La playlist alcanzó su límite',
      },
    });
  } else if (error instanceof PlaylistConflictError) {
    response.status(409).json({
      error: {
        code: 'PLAYLIST_CONFLICT',
        message: 'La playlist cambió; vuelve a cargarla',
      },
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
          error instanceof PlaylistDatabaseError
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
  status = 200,
): RequestHandler {
  return async (request, response) => {
    try {
      const result = await operation(
        request,
        response.locals.auth as AuthIdentity,
      );
      response.status(status).json(result ?? { deleted: true });
    } catch (error) {
      sendError(response, error);
    }
  };
}

function invalid(response: Parameters<RequestHandler>[1]) {
  response.status(400).json({
    error: { code: 'INVALID_REQUEST', message: 'Solicitud inválida' },
  });
}

export function createPlaylistRouter(
  verifier: TokenVerifier,
  service: PlaylistService,
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
  router.post(
    '/',
    async (request, response, next) => {
      const parsed = createBody.safeParse(request.body);
      if (!parsed.success || Object.keys(request.query).length)
        return invalid(response);
      request.body = parsed.data;
      next();
    },
    handler((request, identity) => service.create(identity, request.body), 201),
  );
  router.get(
    '/:playlistId',
    handler(async (request, identity) => {
      const id = playlistId.safeParse(request.params.playlistId);
      if (
        !id.success ||
        Object.keys(request.query).length ||
        request.body !== undefined
      )
        throw new z.ZodError([]);
      return service.detail(identity, id.data);
    }),
  );
  router.patch(
    '/:playlistId',
    async (request, response, next) => {
      const id = playlistId.safeParse(request.params.playlistId);
      const body = updateBody.safeParse(request.body);
      if (!id.success || !body.success || Object.keys(request.query).length)
        return invalid(response);
      request.params.playlistId = id.data;
      request.body = body.data;
      next();
    },
    handler((request, identity) =>
      service.update(
        identity,
        request.params.playlistId as string,
        request.body,
      ),
    ),
  );
  router.delete(
    '/:playlistId',
    handler(async (request, identity) => {
      const id = playlistId.safeParse(request.params.playlistId);
      if (
        !id.success ||
        Object.keys(request.query).length ||
        request.body !== undefined
      )
        throw new z.ZodError([]);
      await service.delete(identity, id.data);
    }),
  );
  router.post(
    '/:playlistId/tracks',
    async (request, response, next) => {
      const id = playlistId.safeParse(request.params.playlistId);
      const body = addBody.safeParse(request.body);
      if (!id.success || !body.success || Object.keys(request.query).length)
        return invalid(response);
      request.params.playlistId = id.data;
      request.body = body.data;
      next();
    },
    handler((request, identity) =>
      service.addTrack(
        identity,
        request.params.playlistId as string,
        request.body.catalogTrackId,
      ),
    ),
  );
  router.delete(
    '/:playlistId/tracks/:itemId',
    handler(async (request, identity) => {
      const id = playlistId.safeParse(request.params.playlistId);
      const item = playlistId.safeParse(request.params.itemId);
      if (
        !id.success ||
        !item.success ||
        Object.keys(request.query).length ||
        request.body !== undefined
      )
        throw new z.ZodError([]);
      return service.removeTrack(identity, id.data, item.data);
    }),
  );
  router.put(
    '/:playlistId/tracks/order',
    async (request, response, next) => {
      const id = playlistId.safeParse(request.params.playlistId);
      const body = orderBody.safeParse(request.body);
      if (!id.success || !body.success || Object.keys(request.query).length)
        return invalid(response);
      request.params.playlistId = id.data;
      request.body = body.data;
      next();
    },
    handler((request, identity) =>
      service.reorder(
        identity,
        request.params.playlistId as string,
        request.body.itemIds,
      ),
    ),
  );
  return router;
}
