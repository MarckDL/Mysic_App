import type { Track } from '../../modules/catalog/domain/music-provider.js';
import {
  FavoriteDatabaseError,
  type FavoriteItem,
} from '../../modules/favorites/domain/favorite.js';
import type { FavoriteRepository } from '../../modules/favorites/domain/favorite-repository.js';
import { getDatabase } from './prisma.js';
import { catalogTrack, upsertTrack } from './prisma-track.js';

const include = { track: true } as const;

function item(value: {
  createdAt: Date;
  track: Parameters<typeof catalogTrack>[0];
}): FavoriteItem {
  return {
    createdAt: value.createdAt.toISOString(),
    track: catalogTrack(value.track),
  };
}

function translate(error: unknown): never {
  throw new FavoriteDatabaseError('No se pudo acceder a favoritos', {
    cause: error,
  });
}

export class PrismaFavoriteRepository implements FavoriteRepository {
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

  async list(ownerId: string) {
    try {
      return (
        await getDatabase().favorite.findMany({
          where: { userId: ownerId },
          orderBy: [{ createdAt: 'desc' }, { trackId: 'asc' }],
          include,
        })
      ).map(item);
    } catch (error) {
      translate(error);
    }
  }

  async find(ownerId: string, source: string, sourceId: string) {
    try {
      const value = await getDatabase().favorite.findFirst({
        where: { userId: ownerId, track: { source, sourceId } },
        include,
      });
      return value ? item(value) : null;
    } catch (error) {
      translate(error);
    }
  }

  async upsert(ownerId: string, track: Track) {
    try {
      return await getDatabase().$transaction(async (transaction) => {
        const stored = await upsertTrack(transaction, track);
        return item(
          await transaction.favorite.upsert({
            where: {
              userId_trackId: { userId: ownerId, trackId: stored.id },
            },
            create: { userId: ownerId, trackId: stored.id },
            update: {},
            include,
          }),
        );
      });
    } catch (error) {
      translate(error);
    }
  }

  async delete(ownerId: string, source: string, sourceId: string) {
    try {
      const track = await getDatabase().track.findUnique({
        where: { source_sourceId: { source, sourceId } },
        select: { id: true },
      });
      if (!track) return false;
      return (
        (
          await getDatabase().favorite.deleteMany({
            where: { userId: ownerId, trackId: track.id },
          })
        ).count === 1
      );
    } catch (error) {
      translate(error);
    }
  }
}
