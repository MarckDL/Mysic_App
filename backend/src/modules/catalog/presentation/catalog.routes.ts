import { Router } from 'express';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type {
  AuthIdentity,
  TokenVerifier,
} from '../../auth/domain/token-verifier.js';
import { ProviderTimeoutError } from '../domain/music-provider.js';
import type { CatalogService } from '../application/catalog-service.js';
import { CatalogLimiter } from '../application/catalog-limiter.js';

export function createCatalogRouter(
  verifier: TokenVerifier,
  service: CatalogService,
  limiter = new CatalogLimiter(),
) {
  const router = Router();
  // El middleware solo afecta catálogo; las rutas anteriores conservan su contrato.
  for (const path of ['/search', '/tracks/:id']) {
    router.get(
      path,
      (_request, response, next) => {
        response.setHeader('Cache-Control', 'no-store');
        next();
      },
      requireAuth(verifier),
      (_request, response, next) => {
        const wait = limiter.consume(
          (response.locals.auth as AuthIdentity).firebaseUid,
        );
        if (wait !== null) {
          response.setHeader('Retry-After', wait);
          response.status(429).json({
            error: {
              code: 'CATALOG_RATE_LIMITED',
              message: 'Espera un momento antes de buscar de nuevo',
            },
          });
          return;
        }
        next();
      },
      async (request, response) => {
        const query = request.query.q;
        const isSearch = path === '/search';
        const cleanQuery =
          typeof query === 'string' ? query.trim().replace(/\s+/gu, ' ') : '';
        const id = request.params.id;
        const valid = isSearch
          ? Object.keys(request.query).length === 1 &&
            typeof query === 'string' &&
            query.length <= 1024 &&
            cleanQuery.length >= 2 &&
            cleanQuery.length <= 120 &&
            !/[\p{Cc}]/u.test(query)
          : Object.keys(request.query).length === 0 &&
            typeof id === 'string' &&
            /^youtube:[A-Za-z0-9_-]{11}$/.test(id);
        if (!valid || request.body !== undefined) {
          response.status(400).json({
            error: {
              code: 'INVALID_REQUEST',
              message: 'Consulta de catálogo inválida',
            },
          });
          return;
        }
        try {
          if (isSearch) {
            response.json({ items: await service.search(cleanQuery) });
          } else {
            const track = await service.getTrack(
              (id as string).slice('youtube:'.length),
            );
            if (!track) {
              response.status(404).json({
                error: {
                  code: 'TRACK_NOT_FOUND',
                  message: 'Pista no encontrada',
                },
              });
              return;
            }
            response.json(track);
          }
        } catch (error) {
          const timeout = error instanceof ProviderTimeoutError;
          response.status(timeout ? 504 : 503).json({
            error: {
              code: timeout ? 'CATALOG_TIMEOUT' : 'CATALOG_UNAVAILABLE',
              message: timeout
                ? 'El catálogo tardó demasiado en responder'
                : 'El catálogo no está disponible. Inténtalo de nuevo',
            },
          });
        }
      },
    );
  }
  return router;
}
