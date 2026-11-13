import type { Track } from '../../modules/catalog/domain/music-provider.js';
import {
  RatingDatabaseError,
  type RatingStatus,
} from '../../modules/ratings/domain/rating.js';
import type { RatingRepository } from '../../modules/ratings/domain/rating-repository.js';
import { getDatabase } from './prisma.js';

function rounded(value: number | null): number | null {
  return value === null ? null : Math.round(value * 100) / 100;
}

function translate(error: unknown): never {
  throw new RatingDatabaseError('No se pudo acceder a calificaciones', {
    cause: error,
  });
}

export class PrismaRatingRepository implements RatingRepository {
  async findUserId(firebaseUid: string): Promise<string | null> {
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

  async status(ownerId: string, catalogTrackId: string): Promise<RatingStatus> {
    try {
      const source = 'youtube';
      const sourceId = catalogTrackId.slice('youtube:'.length);
      const track = await getDatabase().track.findUnique({
        where: { source_sourceId: { source, sourceId } },
        select: { id: true },
      });
      if (!track)
        return { myRating: null, ratingAverage: null, ratingCount: 0 };
      const [mine, aggregate] = await Promise.all([
        getDatabase().rating.findUnique({
          where: { userId_trackId: { userId: ownerId, trackId: track.id } },
          select: { score: true },
        }),
        getDatabase().rating.aggregate({
          where: { trackId: track.id },
          _avg: { score: true },
          _count: { score: true },
        }),
      ]);
      return {
        myRating: mine?.score ?? null,
        ratingAverage: rounded(aggregate._avg.score),
        ratingCount: aggregate._count.score,
      };
    } catch (error) {
      translate(error);
    }
  }

  async upsert(ownerId: string, track: Track, score: number) {
    try {
      return await getDatabase().$transaction(async (transaction) => {
        const stored = await transaction.track.upsert({
          where: {
            source_sourceId: { source: track.source, sourceId: track.sourceId },
          },
          create: {
            source: track.source,
            sourceId: track.sourceId,
            title: track.title,
            artistName: track.artistName,
            durationSeconds: track.durationSeconds,
            thumbnailUrl: track.thumbnailUrl,
          },
          update: {
            title: track.title,
            artistName: track.artistName,
            durationSeconds: track.durationSeconds,
            thumbnailUrl: track.thumbnailUrl,
            metadataUpdatedAt: new Date(),
          },
        });
        const mine = await transaction.rating.upsert({
          where: { userId_trackId: { userId: ownerId, trackId: stored.id } },
          create: { userId: ownerId, trackId: stored.id, score },
          update: { score },
          select: { score: true },
        });
        const aggregate = await transaction.rating.aggregate({
          where: { trackId: stored.id },
          _avg: { score: true },
          _count: { score: true },
        });
        return {
          myRating: mine.score,
          ratingAverage: rounded(aggregate._avg.score),
          ratingCount: aggregate._count.score,
        };
      });
    } catch (error) {
      translate(error);
    }
  }
}
