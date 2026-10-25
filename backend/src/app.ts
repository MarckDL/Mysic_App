import express from 'express';
import { createFirebaseTokenVerifier } from './infrastructure/firebase/firebase-token-verifier.js';
import { createAuthRouter } from './modules/auth/presentation/auth.routes.js';
import type { TokenVerifier } from './modules/auth/domain/token-verifier.js';
import { errorHandler } from './middleware/error.middleware.js';

export function createApp(options: { tokenVerifier?: TokenVerifier } = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '16kb' }));

  // Liveness pública: no comprueba todavía Firebase ni PostgreSQL.
  app.get('/api/v1/health', (_request, response) => {
    response.status(200).json({ status: 'ok' });
  });

  app.use(
    '/api/v1/auth',
    createAuthRouter(options.tokenVerifier ?? createFirebaseTokenVerifier()),
  );

  app.use((_request, response) => {
    response.status(404).json({
      error: { code: 'NOT_FOUND', message: 'Recurso no encontrado' },
    });
  });
  app.use(errorHandler);
  return app;
}
