import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../../middleware/auth.middleware.js';
import type {
  AuthIdentity,
  TokenVerifier,
} from '../../auth/domain/token-verifier.js';
import type { CommentService } from '../application/comment-service.js';
import {
  CommentError,
  reportReasons,
  type PageRequest,
} from '../domain/comment.js';

const catalogId = z.string().regex(/^youtube:[A-Za-z0-9_-]{11}$/);
const id = z.uuid();
const body = z
  .object({
    body: z
      .string()
      .trim()
      .min(1)
      .refine(
        (value) =>
          Array.from(value).length <= 500 &&
          !value.includes('\0') &&
          !/[\uD800-\uDFFF]/u.test(value),
      ),
  })
  .strict();
const report = z.object({ reason: z.enum(reportReasons) }).strict();
const moderation = z.object({ action: z.enum(['hide', 'dismiss']) }).strict();
const noQuery = z.object({}).strict();
const pageQuery = z
  .object({
    limit: z
      .string()
      .regex(/^[1-9][0-9]?$/)
      .transform(Number)
      .pipe(z.number().max(50))
      .optional(),
    cursor: z
      .string()
      .regex(/^[A-Za-z0-9_-]{1,128}$/)
      .optional(),
  })
  .strict();
const cursorShape = z.tuple([z.iso.datetime({ precision: 3 }), id]);

function pageRequest(request: Request): PageRequest {
  if (request.body !== undefined) throw new z.ZodError([]);
  const { cursor, limit = 20 } = pageQuery.parse(request.query);
  if (!cursor) return { limit };
  try {
    const [date, afterId] = cursorShape.parse(
      JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')),
    );
    return { limit, after: { date: new Date(date), id: afterId } };
  } catch {
    throw new z.ZodError([]);
  }
}

function pageResponse<T extends { id: string }>(
  rows: T[],
  limit: number,
  position: (item: T) => Date,
) {
  const items = rows.slice(0, limit);
  const last = items.at(-1);
  const nextCursor =
    last && rows.length > limit
      ? Buffer.from(
          JSON.stringify([position(last).toISOString(), last.id]),
        ).toString('base64url')
      : null;
  return { items, nextCursor };
}

export function createCommentRouter(
  verifier: TokenVerifier,
  service: CommentService,
) {
  const router = Router();
  const auth = requireAuth(verifier);

  function protectedRoute(
    handler: (
      request: Request,
      response: Response,
      identity: AuthIdentity,
    ) => Promise<void>,
  ) {
    return [
      (_request: Request, response: Response, next: () => void) => {
        response.setHeader('Cache-Control', 'no-store');
        next();
      },
      auth,
      async (request: Request, response: Response) => {
        try {
          if (request.method !== 'GET') noQuery.parse(request.query);
          if (request.method === 'DELETE' && request.body !== undefined)
            throw new z.ZodError([]);
          await handler(
            request,
            response,
            response.locals.auth as AuthIdentity,
          );
        } catch (error) {
          if (error instanceof z.ZodError) {
            response.status(400).json({
              error: {
                code: 'INVALID_REQUEST',
                message: 'Solicitud inválida',
              },
            });
          } else if (error instanceof CommentError) {
            response
              .status(error.status)
              .json({ error: { code: error.code, message: error.message } });
          } else {
            response.status(503).json({
              error: {
                code: 'DATABASE_UNAVAILABLE',
                message: 'No se pudo completar la operación',
              },
            });
          }
        }
      },
    ];
  }

  router.get(
    '/tracks/:catalogTrackId/comments',
    ...protectedRoute(async (request, response, identity) => {
      const page = pageRequest(request);
      const rows = await service.list(
        identity,
        catalogId.parse(request.params.catalogTrackId),
        page,
      );
      response.json(pageResponse(rows, page.limit, (item) => item.createdAt));
    }),
  );
  router.post(
    '/tracks/:catalogTrackId/comments',
    ...protectedRoute(async (request, response, identity) => {
      const item = await service.create(
        identity,
        catalogId.parse(request.params.catalogTrackId),
        body.parse(request.body).body,
      );
      response.status(201).json(item);
    }),
  );
  router.patch(
    '/comments/:commentId',
    ...protectedRoute(async (request, response, identity) => {
      response.json(
        await service.edit(
          identity,
          id.parse(request.params.commentId),
          body.parse(request.body).body,
        ),
      );
    }),
  );
  router.delete(
    '/comments/:commentId',
    ...protectedRoute(async (request, response, identity) => {
      await service.remove(identity, id.parse(request.params.commentId));
      response.status(204).end();
    }),
  );
  router.post(
    '/comments/:commentId/reports',
    ...protectedRoute(async (request, response, identity) => {
      await service.report(
        identity,
        id.parse(request.params.commentId),
        report.parse(request.body).reason,
      );
      response.status(204).end();
    }),
  );
  router.get(
    '/moderation/comments',
    ...protectedRoute(async (request, response, identity) => {
      const page = pageRequest(request);
      const rows = await service.queue(identity, page);
      response.json(
        pageResponse(rows, page.limit, (item) => item.firstReportAt),
      );
    }),
  );
  router.patch(
    '/moderation/comments/:commentId',
    ...protectedRoute(async (request, response, identity) => {
      await service.resolve(
        identity,
        id.parse(request.params.commentId),
        moderation.parse(request.body).action,
      );
      response.status(204).end();
    }),
  );

  return router;
}
