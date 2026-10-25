import { Router } from 'express';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type { AuthIdentity, TokenVerifier } from '../domain/token-verifier.js';

import type { UserService } from '../../users/application/user-service.js';
import {
  profileHandler,
  rejectProfileInput,
} from '../../users/presentation/user.routes.js';

export function createAuthRouter(verifier: TokenVerifier, users: UserService) {
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
  router.post(
    '/sync',
    requireAuth(verifier),
    rejectProfileInput,
    profileHandler(users, 'sync'),
  );
  return router;
}
