import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type { TokenVerifier } from '../../auth/domain/token-verifier.js';
import {
  DiscoveryService,
  searchTypes,
  type DiscoveryRequest,
} from '../application/discovery-service.js';
import { CatalogLimiter } from '../application/catalog-limiter.js';

const search = z
  .object({
    q: z
      .string()
      .min(1)
      .max(1024)
      .refine((q) => !/[\p{Cc}]/u.test(q))
      .transform((q) => q.trim().replace(/\s+/gu, ' '))
      .pipe(z.string().min(1).max(120)),
    type: z.enum(searchTypes).default('all'),
  })
  .strict();
const browseIds = {
  artist: /^UC[\w-]{22}$/,
  album: /^(?:MPLA)?MPRE[\w-]{1,140}$/,
  playlist: /^[\w-]{2,145}$/,
};
export function discoveryRouter(
  verifier: TokenVerifier,
  service: DiscoveryService,
  limiter = new CatalogLimiter(),
) {
  const router = Router();
  router.use((_req, res, next) => {
    res.set('Cache-Control', 'private, no-store');
    next();
  }, requireAuth(verifier));
  router.use((req, res, next) => {
    const wait = limiter.consume(res.locals.auth.firebaseUid);
    if (wait) {
      res
        .set('Retry-After', String(wait))
        .status(429)
        .json({
          error: {
            code: 'CATALOG_RATE_LIMITED',
            message: 'Espera un momento antes de volver a buscar.',
          },
        });
      return;
    }
    if (req.body !== undefined) {
      res.status(400).json({
        error: {
          code: 'INVALID_REQUEST',
          message: 'Consulta de catálogo inválida.',
        },
      });
      return;
    }
    next();
  });
  const routes = ['explore', 'search', 'album', 'artist', 'playlist'] as const;
  for (const view of routes) {
    const detail = view !== 'explore' && view !== 'search';
    router.get('/' + view + (detail ? '/:id' : ''), async (req, res) => {
      const hasArgs = Object.keys(req.query).length > 0;
      let request: DiscoveryRequest | undefined;
      if (view === 'search') {
        const parsed = search.safeParse(req.query);
        if (parsed.success)
          request = { view, query: parsed.data.q, type: parsed.data.type };
      } else if (!hasArgs) {
        if (view === 'explore') request = { view };
        else if (
          typeof req.params.id === 'string' &&
          browseIds[view].test(req.params.id)
        )
          request = { view, id: req.params.id };
      }
      if (!request) {
        res.status(400).json({
          error: {
            code: 'INVALID_REQUEST',
            message: 'Consulta de catálogo inválida.',
          },
        });
        return;
      }
      try {
        res.json(await service.read(request));
      } catch {
        res.status(503).json({
          error: {
            code: 'CATALOG_UNAVAILABLE',
            message: 'No se pudo consultar YouTube Music.',
          },
        });
      }
    });
  }
  return router;
}
