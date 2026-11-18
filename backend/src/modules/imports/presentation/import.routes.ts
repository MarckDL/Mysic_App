import { Router, type RequestHandler } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type {
  AuthIdentity,
  TokenVerifier,
} from '../../auth/domain/token-verifier.js';
import { CatalogLimiter } from '../../catalog/application/catalog-limiter.js';
import type { ImportService } from '../application/import-service.js';
import { ImportError, importView } from '../domain/music-import.js';

const uuid = z.string().uuid();
const input = z
  .object({
    id: uuid,
    name: z
      .string()
      .trim()
      .min(1)
      .refine((value) => [...value].length <= 150 && !/[\p{Cc}]/u.test(value)),
    sourceIds: z
      .array(z.string().regex(/^[A-Za-z0-9_-]{11}$/))
      .min(1)
      .max(500),
  })
  .strict();
const batch = z
  .object({
    indices: z
      .array(z.number().int().min(0).max(499))
      .min(1)
      .max(2)
      .refine((values) => new Set(values).size === values.length),
  })
  .strict();

export function createImportRouter(
  verifier: TokenVerifier,
  service: ImportService,
) {
  const router = Router();
  const limiter = new CatalogLimiter(Date.now, 180);
  router.use((_request, response, next) => {
    response.setHeader('Cache-Control', 'no-store');
    next();
  });
  router.use(requireAuth(verifier));
  router.use((_request, response, next) => {
    const wait = limiter.consume(
      (response.locals.auth as AuthIdentity).firebaseUid,
    );
    if (wait !== null) {
      response.setHeader('Retry-After', wait);
      response.status(429).json({
        error: {
          code: 'IMPORT_RATE_LIMITED',
          message: 'Espera un minuto antes de continuar',
        },
      });
      return;
    }
    next();
  });

  const handle =
    (
      operation: (
        request: Parameters<RequestHandler>[0],
        identity: AuthIdentity,
      ) => Promise<unknown>,
    ): RequestHandler =>
    async (request, response) => {
      try {
        if (Object.keys(request.query).length) throw new z.ZodError([]);
        response.json(
          await operation(request, response.locals.auth as AuthIdentity),
        );
      } catch (error) {
        if (error instanceof z.ZodError) {
          response.status(400).json({
            error: { code: 'INVALID_REQUEST', message: 'Solicitud inválida' },
          });
        } else if (error instanceof ImportError) {
          if (error.status === 429) response.setHeader('Retry-After', '5');
          response
            .status(error.status)
            .json({ error: { code: error.code, message: error.message } });
        } else {
          response.status(503).json({
            error: {
              code: 'IMPORT_UNAVAILABLE',
              message: 'No se pudo completar la importación',
            },
          });
        }
      }
    };
  router.post(
    '/',
    handle(async (request, identity) =>
      importView(await service.prepare(identity, input.parse(request.body))),
    ),
  );
  router.get(
    '/',
    handle(async (request, identity) => {
      if (request.body !== undefined) throw new z.ZodError([]);
      return { items: (await service.list(identity)).map(importView) };
    }),
  );
  router.get(
    '/:id',
    handle(async (request, identity) => {
      if (request.body !== undefined) throw new z.ZodError([]);
      return importView(
        await service.get(identity, uuid.parse(request.params.id)),
      );
    }),
  );
  router.post(
    '/:id/resolve',
    handle(async (request, identity) =>
      importView(
        await service.resolve(
          identity,
          uuid.parse(request.params.id),
          batch.parse(request.body).indices,
        ),
      ),
    ),
  );
  router.post(
    '/:id/confirm',
    handle(async (request, identity) => {
      z.object({}).strict().parse(request.body);
      return importView(
        await service.confirm(identity, uuid.parse(request.params.id)),
      );
    }),
  );
  router.delete(
    '/:id',
    handle(async (request, identity) => {
      if (request.body !== undefined) throw new z.ZodError([]);
      await service.discard(identity, uuid.parse(request.params.id));
      return { deleted: true };
    }),
  );
  return router;
}
