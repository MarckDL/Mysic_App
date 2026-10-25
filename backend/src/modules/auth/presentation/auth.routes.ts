import { Router } from 'express';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type { AuthIdentity, TokenVerifier } from '../domain/token-verifier.js';

export function createAuthRouter(verifier: TokenVerifier) {
  const router = Router();
  router.use((_request, response, next) => {
    response.setHeader('Cache-Control', 'no-store');
    next();
  });
  router.get('/session', requireAuth(verifier), (_request, response) => {
    const identity = response.locals.auth as AuthIdentity;
    response.json({
      firebaseUid: identity.firebaseUid,
      provider: identity.provider,
    });
  });
  return router;
}
