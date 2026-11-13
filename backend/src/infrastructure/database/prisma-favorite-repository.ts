import type { Track } from '../../modules/catalog/domain/music-provider.js';
import {
  FavoriteDatabaseError,
  type FavoriteItem,
} from '../../modules/favorites/domain/favorite.js';
import type { FavoriteRepository } from '../../modules/favorites/domain/favorite-repository.js';
import { getDatabase } from './prisma.js';

function catalogTrack(record: {
  source: string;
  sourceId: string;
  title: string;
  artistName: string;
  durationSeconds: number | null;
  thumbnailUrl: string | null;
}): Track {
  return {
    id: `${record.source}:${record.sourceId}`,
    source: record.source as Track['source'],
    sourceId: record.sourceId,
    title: record.title,
    artistName: record.artistName,
    durationSeconds: record.durationSeconds,
    thumbnailUrl: record.thumbnailUrl,
  };
}

function translate(error: unknown): never {
  throw new FavoriteDatabaseError('No se pudo acceder a favoritos', {
    cause: error,
  });
}

export class PrismaFavoriteRepository implements FavoriteRepository {
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

  async list(ownerId: string): Promise<FavoriteItem[]> {
    try {
      return (
        await getDatabase().favorite.findMany({
          where: { userId: ownerId },
          include: { track: true },
          orderBy: [{ createdAt: 'desc' }, { trackId: 'asc' }],
        })
      ).map((favorite) => ({
        createdAt: favorite.createdAt.toISOString(),
        track: catalogTrack(favorite.track),
      }));
    } catch (error) {
      translate(error);
    }
  }

  async has(ownerId: string, catalogTrackId: string): Promise<boolean> {
    try {
      const source = 'youtube';
      const sourceId = catalogTrackId.slice('youtube:'.length);
      return Boolean(
        await getDatabase().favorite.findFirst({
          where: { userId: ownerId, track: { source, sourceId } },
          select: { userId: true },
        }),
      );
    } catch (error) {
      translate(error);
    }
  }

  async add(ownerId: string, track: Track): Promise<void> {
    try {
      await getDatabase().$transaction(async (transaction) => {
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
        await transaction.favorite.upsert({
          where: { userId_trackId: { userId: ownerId, trackId: stored.id } },
          create: { userId: ownerId, trackId: stored.id },
          update: {},
        });
      });
    } catch (error) {
      translate(error);
    }
  }

  async remove(ownerId: string, catalogTrackId: string): Promise<void> {
    try {
      const source = 'youtube';
      const sourceId = catalogTrackId.slice('youtube:'.length);
      await getDatabase().favorite.deleteMany({
        where: { userId: ownerId, track: { source, sourceId } },
      });
    } catch (error) {
      translate(error);
    }
  }
}
