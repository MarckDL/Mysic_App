import express from 'express';
import { errorHandler } from './middleware/error.middleware.js';

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '16kb' }));

  // Liveness pública: no comprueba todavía Firebase ni PostgreSQL.
  app.get('/api/v1/health', (_request, response) => {
    response.status(200).json({ status: 'ok' });
  });

  app.use((_request, response) => {
    response.status(404).json({
      error: { code: 'NOT_FOUND', message: 'Recurso no encontrado' },
    });
  });
  app.use(errorHandler);
  return app;
}
