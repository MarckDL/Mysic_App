import type { Prisma } from '../../generated/prisma/client.js';
import type { Track } from '../../modules/catalog/domain/music-provider.js';
import {
  RatingDatabaseError,
  type RatingSummary,
} from '../../modules/ratings/domain/rating.js';
import type { RatingRepository } from '../../modules/ratings/domain/rating-repository.js';
import { getDatabase } from './prisma.js';
import { upsertTrack } from './prisma-track.js';

function translate(error: unknown): never {
  throw new RatingDatabaseError('No se pudo acceder a calificaciones', {
    cause: error,
  });
}

async function summary(
  database: Prisma.TransactionClient,
  ownerId: string,
  trackId: string,
): Promise<RatingSummary> {
  const [own, aggregate] = await Promise.all([
    database.rating.findUnique({
      where: { userId_trackId: { userId: ownerId, trackId } },
      select: { score: true },
    }),
    database.rating.aggregate({
      where: { trackId },
      _avg: { score: true },
      _count: { score: true },
    }),
  ]);
  return {
    myScore: own?.score ?? null,
    averageScore: aggregate._avg.score,
    ratingCount: aggregate._count.score,
  };
}

export class PrismaRatingRepository implements RatingRepository {
  async findUserId(firebaseUid: string) {
    try {
      return (
        (
          await getDatabase().user.findUnique({
            where: { firebaseUid },
            select: { id: true },
          })
        )?.id ?? null
      );
    } catch (error) {
      translate(error);
    }
  }

  async get(ownerId: string, source: string, sourceId: string) {
    try {
      const track = await getDatabase().track.findUnique({
        where: { source_sourceId: { source, sourceId } },
        select: { id: true },
      });
      return track
        ? await getDatabase().$transaction((transaction) =>
            summary(transaction, ownerId, track.id),
          )
        : { myScore: null, averageScore: null, ratingCount: 0 };
    } catch (error) {
      translate(error);
    }
  }

  async upsert(ownerId: string, track: Track, score: number) {
    try {
      return await getDatabase().$transaction(async (transaction) => {
        const stored = await upsertTrack(transaction, track);
        await transaction.rating.upsert({
          where: {
            userId_trackId: { userId: ownerId, trackId: stored.id },
          },
          create: { userId: ownerId, trackId: stored.id, score },
          update: { score },
        });
        return summary(transaction, ownerId, stored.id);
      });
    } catch (error) {
      translate(error);
    }
  }

  async delete(ownerId: string, source: string, sourceId: string) {
    try {
      return await getDatabase().$transaction(async (transaction) => {
        const track = await transaction.track.findUnique({
          where: { source_sourceId: { source, sourceId } },
          select: { id: true },
        });
        if (!track)
          return { myScore: null, averageScore: null, ratingCount: 0 };
        await transaction.rating.deleteMany({
          where: { userId: ownerId, trackId: track.id },
        });
        return summary(transaction, ownerId, track.id);
      });
    } catch (error) {
      translate(error);
    }
  }
}
