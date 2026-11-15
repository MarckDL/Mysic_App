import { Prisma } from '../../generated/prisma/client.js';
import type { Track } from '../../modules/catalog/domain/music-provider.js';
import {
  CommentError,
  type CommentRepository,
  type ModerationAction,
  type ModerationItem,
  type PageRequest,
  type ReportReason,
} from '../../modules/comments/domain/comment.js';
import { getDatabase } from './prisma.js';

const withAuthor = { user: { select: { displayName: true } } } as const;
type StoredComment = Prisma.CommentGetPayload<{ include: typeof withAuthor }>;

function present(comment: StoredComment, userId: string) {
  return {
    id: comment.id,
    body: comment.body,
    authorName: comment.user.displayName,
    createdAt: comment.createdAt,
    updatedAt: comment.updatedAt,
    isMine: comment.userId === userId,
  };
}

async function lockComment(transaction: Prisma.TransactionClient, id: string) {
  // Todas las mutaciones sobre un comentario adquieren este mismo bloqueo.
  await transaction.$queryRaw`SELECT id FROM mysic.comments WHERE id = ${id}::uuid FOR UPDATE`;
  const comment = await transaction.comment.findUnique({ where: { id } });
  if (!comment) throw new CommentError('COMMENT_NOT_FOUND');
  return comment;
}

function requireVisible(comment: { status: string }) {
  if (comment.status !== 'visible') throw new CommentError('COMMENT_NOT_FOUND');
}

export class PrismaCommentRepository implements CommentRepository {
  async findUserId(firebaseUid: string) {
    const user = await getDatabase().user.findUnique({
      where: { firebaseUid },
      select: { id: true },
    });
    return user?.id ?? null;
  }

  async list(userId: string, sourceId: string, { limit, after }: PageRequest) {
    const items = await getDatabase().comment.findMany({
      where: {
        track: { source: 'youtube', sourceId },
        status: 'visible',
        ...(after
          ? {
              OR: [
                { createdAt: { lt: after.date } },
                { createdAt: after.date, id: { lt: after.id } },
              ],
            }
          : {}),
      },
      include: withAuthor,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    return items.map((item) => present(item, userId));
  }

  async create(userId: string, track: Track, body: string) {
    return getDatabase().$transaction(async (transaction) => {
      const {
        source,
        sourceId,
        title,
        artistName,
        durationSeconds,
        thumbnailUrl,
      } = track;
      const stored = await transaction.track.upsert({
        where: { source_sourceId: { source, sourceId } },
        create: {
          source,
          sourceId,
          title,
          artistName,
          durationSeconds,
          thumbnailUrl,
        },
        update: {
          title,
          artistName,
          durationSeconds,
          thumbnailUrl,
          metadataUpdatedAt: new Date(),
        },
        select: { id: true },
      });
      const comment = await transaction.comment.create({
        data: { userId, trackId: stored.id, body },
        include: withAuthor,
      });
      return present(comment, userId);
    });
  }

  async edit(userId: string, id: string, body: string) {
    return getDatabase().$transaction(async (transaction) => {
      const comment = await lockComment(transaction, id);
      requireVisible(comment);
      if (comment.userId !== userId) throw new CommentError('FORBIDDEN');
      return present(
        await transaction.comment.update({
          where: { id },
          data: { body },
          include: withAuthor,
        }),
        userId,
      );
    });
  }

  async remove(userId: string, id: string) {
    await getDatabase().$transaction(async (transaction) => {
      const comment = await lockComment(transaction, id);
      requireVisible(comment);
      if (comment.userId !== userId) throw new CommentError('FORBIDDEN');
      await transaction.comment.update({
        where: { id },
        data: { status: 'deleted' },
      });
      await transaction.commentReport.updateMany({
        where: { commentId: id, status: 'pending' },
        data: { status: 'deleted', resolvedAt: new Date() },
      });
    });
  }

  async report(userId: string, id: string, reason: ReportReason) {
    await getDatabase().$transaction(async (transaction) => {
      const comment = await lockComment(transaction, id);
      if (comment.userId === userId) throw new CommentError('FORBIDDEN');
      const existing = await transaction.commentReport.findUnique({
        where: { commentId_reporterId: { commentId: id, reporterId: userId } },
        select: { commentId: true },
      });
      if (existing) return;
      requireVisible(comment);
      await transaction.commentReport.create({
        data: { commentId: id, reporterId: userId, reason },
      });
    });
  }

  async queue({ limit, after }: PageRequest) {
    const position = after
      ? Prisma.sql`HAVING (min(r.created_at), c.id) > (${after.date}, ${after.id}::uuid)`
      : Prisma.empty;
    return getDatabase().$queryRaw<ModerationItem[]>`
      SELECT c.id, c.body, u.display_name AS "authorName",
             c.created_at AS "createdAt", c.updated_at AS "updatedAt",
             min(r.created_at) AS "firstReportAt",
             array_agg(DISTINCT r.reason::text ORDER BY r.reason::text) AS reasons
      FROM mysic.comment_reports r
      JOIN mysic.comments c ON c.id = r.comment_id
      JOIN mysic.users u ON u.id = c.user_id
      WHERE r.status = 'pending' AND c.status = 'visible'
      GROUP BY c.id, u.id
      ${position}
      ORDER BY "firstReportAt", c.id
      LIMIT ${limit + 1}
    `;
  }

  async resolve(userId: string, id: string, action: ModerationAction) {
    await getDatabase().$transaction(async (transaction) => {
      const comment = await lockComment(transaction, id);
      if (comment.status !== 'visible')
        throw new CommentError('REPORTS_ALREADY_RESOLVED');
      const reports = await transaction.commentReport.updateMany({
        where: { commentId: id, status: 'pending' },
        data: {
          status: action === 'hide' ? 'hidden' : 'dismissed',
          moderatorId: userId,
          resolvedAt: new Date(),
        },
      });
      if (!reports.count) throw new CommentError('REPORTS_ALREADY_RESOLVED');
      if (action === 'hide') {
        await transaction.comment.update({
          where: { id },
          data: { status: 'hidden' },
        });
      }
    });
  }
}
