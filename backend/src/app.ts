import express from 'express';
import { createFirebaseTokenVerifier } from './infrastructure/firebase/firebase-token-verifier.js';
import { createAuthRouter } from './modules/auth/presentation/auth.routes.js';
import type { TokenVerifier } from './modules/auth/domain/token-verifier.js';
import { errorHandler } from './middleware/error.middleware.js';

import { PrismaUserRepository } from './infrastructure/database/prisma-user-repository.js';
import { UserService } from './modules/users/application/user-service.js';
import type { UserRepository } from './modules/users/domain/user-repository.js';
import { createUsersRouter } from './modules/users/presentation/user.routes.js';

import { YoutubeProvider } from './infrastructure/music/youtube-provider.js';
import { CatalogService } from './modules/catalog/application/catalog-service.js';
import { CatalogLimiter } from './modules/catalog/application/catalog-limiter.js';
import type { MusicProvider } from './modules/catalog/domain/music-provider.js';
import { createCatalogRouter } from './modules/catalog/presentation/catalog.routes.js';

import { AuthorizedDemoProvider } from './infrastructure/music/authorized-demo-provider.js';
import { PlaybackService } from './modules/playback/application/playback-service.js';
import { createPlaybackRouter } from './modules/playback/presentation/playback.routes.js';

export function createApp(
  options: {
    tokenVerifier?: TokenVerifier;
    userRepository?: UserRepository;
    musicProvider?: MusicProvider;
    catalogService?: CatalogService;
    catalogLimiter?: CatalogLimiter;
    playbackService?: PlaybackService;
  } = {},
) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '16kb' }));

  // Liveness pública: no comprueba todavía Firebase ni PostgreSQL.
  app.get('/api/v1/health', (_request, response) => {
    response.status(200).json({ status: 'ok' });
  });

  const verifier = options.tokenVerifier ?? createFirebaseTokenVerifier();
  const users = new UserService(
    options.userRepository ?? new PrismaUserRepository(),
  );
  app.use('/api/v1/auth', createAuthRouter(verifier, users));
  app.use('/api/v1/users', createUsersRouter(verifier, users));
  const music = options.musicProvider ?? new YoutubeProvider();
  app.use(
    '/api/v1/playback',
    createPlaybackRouter(
      verifier,
      options.playbackService ??
        new PlaybackService(
          new Map([
            ['youtube', music],
            ['demo', new AuthorizedDemoProvider()],
          ]),
        ),
    ),
  );
  app.use(
    '/api/v1',
    createCatalogRouter(
      verifier,
      options.catalogService ?? new CatalogService(music),
      options.catalogLimiter,
    ),
  );

  app.use((_request, response) => {
    response.status(404).json({
      error: { code: 'NOT_FOUND', message: 'Recurso no encontrado' },
    });
  });
  app.use(errorHandler);
  return app;
}
