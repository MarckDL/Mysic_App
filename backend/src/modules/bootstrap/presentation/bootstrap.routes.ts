import { Router, type ErrorRequestHandler } from 'express';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type { TokenVerifier } from '../../auth/domain/token-verifier.js';
import type { UserService } from '../../users/application/user-service.js';
import type { AccountMusicService } from '../../integrations/youtube-music/account-service.js';
import type { YoutubeLinkService } from '../../integrations/youtube/link-service.js';
import { LinkError } from '../../integrations/youtube/domain.js';

export function createBootstrapRouter(
  verifier: TokenVerifier,
  users: UserService,
  link: YoutubeLinkService | null | undefined,
  music: AccountMusicService | undefined,
) {
  const router = Router();
  router.use((_request, response, next) => {
    response.setHeader('Cache-Control', 'private, no-store');
    next();
  });
  router.get('/', requireAuth(verifier), async (request, response) => {
    const identity = response.locals.auth;
    const profile = await users.sync(identity);
    link?.rememberOwner(identity.firebaseUid, profile.id);
    if (!music) {
      response.json({ profile, connection: null, home: null });
      return;
    }
    const connection = await music.connection(identity.firebaseUid);
    const abort = new AbortController();
    response.on('close', () => abort.abort());
    const home =
      connection.status === 'linked' && connection.generation
        ? await music.read(
            identity.firebaseUid,
            connection.generation,
            { surface: 'home' },
            20,
            undefined,
            abort.signal,
          )
        : null;
    response.json({ profile, connection, home });
  });
  const handle: ErrorRequestHandler = (error, _request, response, next) => {
    if (!(error instanceof LinkError)) return next(error);
    if (error.retryAfter) response.setHeader('Retry-After', error.retryAfter);
    response.status(error.status).json({
      error: { code: error.code, message: 'No se pudo preparar el inicio.' },
    });
  };
  router.use(handle);
  return router;
}
