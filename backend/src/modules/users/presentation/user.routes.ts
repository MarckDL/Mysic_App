import { Router, type RequestHandler } from 'express';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type {
  AuthIdentity,
  TokenVerifier,
} from '../../auth/domain/token-verifier.js';
import type { UserService } from '../application/user-service.js';
import { UserConflictError } from '../domain/user-repository.js';

// Los endpoints no aceptan parámetros que puedan seleccionar otra identidad.
export const rejectProfileInput: RequestHandler = (request, response, next) => {
  if (
    Object.keys(request.query).length > 0 ||
    (request.body !== undefined &&
      (request.body === null ||
        typeof request.body !== 'object' ||
        Array.isArray(request.body) ||
        Object.keys(request.body).length > 0))
  ) {
    response.status(400).json({
      error: { code: 'INVALID_REQUEST', message: 'Solicitud inválida' },
    });
    return;
  }
  next();
};

export function profileHandler(
  service: UserService,
  operation: 'sync' | 'me',
): RequestHandler {
  return async (_request, response) => {
    try {
      const identity = response.locals.auth as AuthIdentity;
      const user = await service[operation](identity);
      if (!user) {
        response.status(404).json({
          error: {
            code: 'USER_NOT_SYNCED',
            message: 'Sincroniza tu perfil para continuar',
          },
        });
        return;
      }
      response.status(200).json(user);
    } catch (error) {
      const conflict = error instanceof UserConflictError;
      response.status(conflict ? 409 : 503).json({
        error: {
          code: conflict ? 'IDENTITY_CONFLICT' : 'DATABASE_UNAVAILABLE',
          message: conflict
            ? 'No se pudo asociar la identidad'
            : 'No se pudo acceder al perfil',
        },
      });
    }
  };
}

export function createUsersRouter(
  verifier: TokenVerifier,
  service: UserService,
) {
  const router = Router();
  router.use((_request, response, next) => {
    response.setHeader('Cache-Control', 'no-store');
    next();
  });
  router.get(
    '/me',
    requireAuth(verifier),
    rejectProfileInput,
    profileHandler(service, 'me'),
  );
  return router;
}
