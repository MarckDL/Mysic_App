import type { RequestHandler } from 'express';
import {
  InvalidTokenError,
  type TokenVerifier,
} from '../modules/auth/domain/token-verifier.js';

export function requireAuth(verifier: TokenVerifier): RequestHandler {
  return async (request, response, next) => {
    const authorization = request.get('authorization');
    const match = authorization?.match(/^Bearer ([^\s,]+)$/i);
    if (!match?.[1] || match[1].length > 16_384) {
      response.setHeader('WWW-Authenticate', 'Bearer');
      response.status(401).json({
        error: {
          code: 'UNAUTHENTICATED',
          message: 'Se requiere una sesión válida',
        },
      });
      return;
    }
    try {
      const identity = await verifier.verify(match[1]);
      if (identity.provider !== 'google.com') {
        response.status(403).json({
          error: {
            code: 'GOOGLE_REQUIRED',
            message: 'Inicia sesión con Google',
          },
        });
        return;
      }
      // Identidad exclusivamente verificada. No se lee user_id del cliente.
      response.locals.auth = identity;
      next();
    } catch (error) {
      if (error instanceof InvalidTokenError) {
        response.setHeader('WWW-Authenticate', 'Bearer error="invalid_token"');
        response.status(401).json({
          error: {
            code: 'UNAUTHENTICATED',
            message: 'Se requiere una sesión válida',
          },
        });
        return;
      }
      response.status(503).json({
        error: {
          code: 'AUTH_UNAVAILABLE',
          message: 'No se pudo verificar la sesión',
        },
      });
    }
  };
}
