import { randomUUID } from 'node:crypto';
import { Router, type ErrorRequestHandler } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type { TokenVerifier } from '../../auth/domain/token-verifier.js';
import { CatalogLimiter } from '../../catalog/application/catalog-limiter.js';
import { LinkError, ttl } from './domain.js';
import type { YoutubeLinkService } from './link-service.js';

const ref = z.string().regex(/^[A-Za-z0-9_-]{43}$/);
const cookieName = '__Host-mysic-youtube';
const cookieOptions = {
  secure: true,
  httpOnly: true,
  sameSite: 'lax' as const,
  path: '/',
};
const htmlEscape = (s: string) =>
  s
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
const startBody = z.object({ forceConsent: z.boolean().optional() }).strict();
const confirmBody = z
  .object({
    returnRef: ref.optional(),
    channelId: z.string().min(1).max(150).optional(),
    replace: z.boolean().optional(),
  })
  .strict();
const callbackQuery = z
  .object({
    state: ref,
    code: z.string().min(1).max(4096).optional(),
    error: z.string().min(1).max(128).optional(),
  })
  .refine((x) => Boolean(x.code) !== Boolean(x.error));
export function youtubeRouter(
  verifier: TokenVerifier,
  service: YoutubeLinkService | null,
) {
  const router = Router();
  const publicLimit = new CatalogLimiter(Date.now, 120);
  const startLimit = new CatalogLimiter(Date.now, 10);
  const configured = () => {
    if (!service) throw new LinkError(503, 'LINK_DISABLED');
    return service;
  };
  router.use((_req, res, next) => {
    res.set({
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer',
      'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy':
        "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
    });
    next();
  });
  router.use(['/browser/start', '/oauth/callback'], (req, res, next) => {
    const retry = publicLimit.consume(req.ip ?? 'unknown');
    if (retry) {
      res.set('Retry-After', String(retry));
      throw new LinkError(429, 'TOO_MANY_REQUESTS');
    }
    next();
  });
  router.get('/browser/start', async (req, res) => {
    const { cookie, url } = await configured().begin(ref.parse(req.query.ref));
    res
      .cookie(cookieName, cookie, { ...cookieOptions, maxAge: ttl })
      .redirect(302, url);
  });
  router.get('/oauth/callback', async (req, res) => {
    const query = callbackQuery.parse(req.query);
    const cookie = (req.get('Cookie') ?? '')
      .split(';')
      .map((s) => s.trim())
      .find((s) => s.startsWith(cookieName + '='))
      ?.slice(cookieName.length + 1);
    if (!ref.safeParse(cookie).success)
      throw new LinkError(409, 'STALE_ATTEMPT');
    const target = await configured().finish(
      query.state,
      cookie!,
      query.code,
      query.error,
    );
    const nonce = randomUUID();
    res.clearCookie(cookieName, cookieOptions);
    res.set(
      'Content-Security-Policy',
      `default-src 'none'; script-src 'nonce-${nonce}'; frame-ancestors 'none'; base-uri 'none'`,
    );
    res
      .type('html')
      .send(
        `<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Volver a Mysic</title><p><a id="return" href="${htmlEscape(target)}">Volver a Mysic</a></p><script nonce="${nonce}">location.replace(document.getElementById("return").href)</script></html>`,
      );
  });
  router.use(requireAuth(verifier));
  router.use(async (_req, res, next) => {
    if (service)
      res.locals.youtubeOwner = await service.owner(
        res.locals.auth.firebaseUid,
      );
    next();
  });
  router.post('/link-attempts', async (req, res) => {
    const s = configured(),
      user = res.locals.youtubeOwner;
    const retry = startLimit.consume(user);
    if (retry) {
      res.set('Retry-After', String(retry));
      throw new LinkError(429, 'TOO_MANY_REQUESTS');
    }
    const { forceConsent } = startBody.parse(req.body ?? {});
    const key = z.uuid().parse(req.get('Idempotency-Key') ?? randomUUID());
    res.status(201).json(await s.start(user, key, forceConsent ?? false));
  });
  router.get('/link-attempts/:id', async (req, res) => {
    res.json(
      await configured().attempt(
        res.locals.youtubeOwner,
        z.uuid().parse(req.params.id),
      ),
    );
  });
  router.post('/link-attempts/:id/confirm', async (req, res) => {
    res.json(
      await configured().confirm(
        res.locals.youtubeOwner,
        z.uuid().parse(req.params.id),
        confirmBody.parse(req.body),
      ),
    );
  });
  router.get('/connection', async (_req, res) =>
    res.json(
      service
        ? await service.connection(res.locals.youtubeOwner)
        : { status: 'unlinked', channel: null },
    ),
  );
  router.delete('/connection', async (_req, res) => {
    const pending = service
      ? await service.unlink(res.locals.youtubeOwner)
      : false;
    res.status(pending ? 202 : 204).end();
  });
  const handle: ErrorRequestHandler = (error, _req, res, next) => {
    if (error instanceof z.ZodError) {
      res.status(400).json({
        error: { code: 'INVALID_REQUEST', message: 'Solicitud inválida' },
      });
      return;
    }
    if (error instanceof LinkError) {
      res.status(error.status).json({
        error: {
          code: error.code,
          message: 'Consulta el estado de la conexión de YouTube.',
        },
      });
      return;
    }
    next(error);
  };
  router.use(handle);
  return router;
}
