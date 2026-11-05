import { Router } from 'express';
import { pipeline } from 'node:stream/promises';
import type {
  TokenVerifier,
  AuthIdentity,
} from '../../auth/domain/token-verifier.js';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import {
  InvalidAudioRangeError,
  type AudioStreamTransport,
} from '../../../infrastructure/music/youtube-audio-stream.js';
import { CatalogLimiter } from '../../catalog/application/catalog-limiter.js';

export function createAudioStreamRouter(
  verifier: TokenVerifier,
  transport: AudioStreamTransport,
) {
  const router = Router();
  const active = new Map<string, AbortController>();
  const prefetching = new Map<string, AbortController>();
  const limiter = new CatalogLimiter();
  router.post(
    '/prefetch/:sourceId',
    requireAuth(verifier),
    async (request, response) => {
      response.setHeader('Cache-Control', 'no-store');
      const uid = (response.locals.auth as AuthIdentity).firebaseUid;
      const sourceId = request.params.sourceId;
      if (
        typeof sourceId !== 'string' ||
        !/^[A-Za-z0-9_-]{11}$/.test(sourceId) ||
        Object.keys(request.query).length ||
        (request.body !== undefined &&
          (request.body === null ||
            typeof request.body !== 'object' ||
            Array.isArray(request.body) ||
            Object.keys(request.body as object).length > 0))
      ) {
        response.status(400).json({
          error: { code: 'INVALID_REQUEST', message: 'Pista inválida' },
        });
        return;
      }
      const wait = limiter.consume(uid);
      const previous = prefetching.get(uid);
      if (wait !== null || (!previous && prefetching.size >= 2)) {
        response.setHeader('Retry-After', wait ?? 2);
        response.status(429).end();
        return;
      }
      const controller = new AbortController();
      previous?.abort();
      prefetching.set(uid, controller);
      const cancel = () => controller.abort();
      request.once('aborted', cancel);
      try {
        await transport.prefetch(sourceId, controller.signal);
        if (!controller.signal.aborted) response.status(204).end();
      } catch {
        if (!response.headersSent && !response.destroyed)
          response.status(503).end();
      } finally {
        if (prefetching.get(uid) === controller) prefetching.delete(uid);
        request.off('aborted', cancel);
      }
    },
  );
  router.get(
    '/audio/:sourceId',
    requireAuth(verifier),
    async (request, response) => {
      response.setHeader('Cache-Control', 'no-store');
      response.setHeader('X-Content-Type-Options', 'nosniff');
      const uid = (response.locals.auth as AuthIdentity).firebaseUid;
      const sourceId = request.params.sourceId;
      if (request.method === 'HEAD') {
        response.setHeader('Allow', 'GET');
        response.status(405).end();
        return;
      }
      if (
        typeof sourceId !== 'string' ||
        !/^[A-Za-z0-9_-]{11}$/.test(sourceId) ||
        Object.keys(request.query).length
      ) {
        response.status(400).json({
          error: { code: 'INVALID_REQUEST', message: 'Pista inválida' },
        });
        return;
      }
      const wait = limiter.consume(uid);
      const previous = active.get(uid);
      if (wait !== null || (!previous && active.size >= 2)) {
        response.setHeader('Retry-After', wait ?? 2);
        response.status(429).json({
          error: {
            code: 'PLAYBACK_BUSY',
            message: 'Detén el audio anterior e inténtalo de nuevo',
          },
        });
        return;
      }
      const range = request.headers.range;
      if (range && !/^bytes=\d*-\d*$/.test(range)) {
        response.status(416).end();
        return;
      }
      const controller = new AbortController();
      // Los controles siguiente/anterior abren la nueva pista apenas just_audio
      // termina stop(). El cierre HTTP anterior puede llegar unos milisegundos
      // después: se reemplaza solo el stream del mismo usuario en vez de fallar
      // con 429, sin ampliar el límite global de usuarios concurrentes.
      previous?.abort();
      active.set(uid, controller);
      const cancel = () => controller.abort();
      response.once('close', cancel);
      try {
        const audio = await transport.open(sourceId, controller.signal, range);
        if (controller.signal.aborted) {
          audio.stream.destroy();
          return;
        }
        response.status(audio.status);
        response.setHeader('Content-Type', audio.contentType);
        response.setHeader('Content-Length', audio.contentLength);
        response.setHeader('Accept-Ranges', 'bytes');
        if (audio.contentRange)
          response.setHeader('Content-Range', audio.contentRange);
        await pipeline(audio.stream, response, { signal: controller.signal });
      } catch (error) {
        if (!response.headersSent && !response.destroyed) {
          if (error instanceof InvalidAudioRangeError) {
            if (error.contentLength)
              response.setHeader(
                'Content-Range',
                `bytes */${error.contentLength}`,
              );
            response.status(416).end();
          } else
            response.status(503).json({
              error: {
                code: 'PLAYBACK_UNAVAILABLE',
                message: 'No se pudo abrir el audio de esta pista',
              },
            });
        } else if (!response.destroyed) response.destroy();
      } finally {
        cancel();
        if (active.get(uid) === controller) active.delete(uid);
        response.off('close', cancel);
      }
    },
  );
  return router;
}
