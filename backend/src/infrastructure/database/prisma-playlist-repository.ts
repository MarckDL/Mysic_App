import { Prisma } from '../../generated/prisma/client.js';
import { PlaylistVisibility as DatabaseVisibility } from '../../generated/prisma/enums.js';
import type { Track } from '../../modules/catalog/domain/music-provider.js';
import {
  PlaylistCapacityError,
  PlaylistConflictError,
  PlaylistDatabaseError,
  PlaylistInvalidOrderError,
  type PlaylistDetail,
  type PlaylistInput,
  type PlaylistSummary,
  type PlaylistUpdate,
  type PlaylistVisibility,
} from '../../modules/playlists/domain/playlist.js';
import type { PlaylistRepository } from '../../modules/playlists/domain/playlist-repository.js';
import { getDatabase } from './prisma.js';

const detailInclude = {
  tracks: {
    orderBy: { position: 'asc' as const },
    include: { track: true },
  },
  _count: { select: { tracks: true } },
};

type DetailRecord = Prisma.PlaylistGetPayload<{
  include: typeof detailInclude;
}>;

function visibility(value: DatabaseVisibility): PlaylistVisibility {
  return value === DatabaseVisibility.PUBLIC ? 'public' : 'private';
}

function databaseVisibility(value: PlaylistVisibility): DatabaseVisibility {
  return value === 'public'
    ? DatabaseVisibility.PUBLIC
    : DatabaseVisibility.PRIVATE;
}

function summary(value: DetailRecord): PlaylistSummary {
  return {
    id: value.id,
    name: value.name,
    description: value.description,
    visibility: visibility(value.visibility),
    trackCount: value._count.tracks,
    createdAt: value.createdAt.toISOString(),
    updatedAt: value.updatedAt.toISOString(),
  };
}

function detail(value: DetailRecord, ownerId: string): PlaylistDetail {
  return {
    ...summary(value),
    ownedByCurrentUser: value.userId === ownerId,
    tracks: value.tracks.map((item) => ({
      id: item.id,
      position: item.position,
      addedAt: item.addedAt.toISOString(),
      track: {
        id: `${item.track.source}:${item.track.sourceId}`,
        source: item.track.source as Track['source'],
        sourceId: item.track.sourceId,
        title: item.track.title,
        artistName: item.track.artistName,
        durationSeconds: item.track.durationSeconds,
        thumbnailUrl: item.track.thumbnailUrl,
      },
    })),
  };
}

function isRetryableConflict(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    (error.code === 'P2034' || error.code === 'P2002')
  );
}

function translate(error: unknown): never {
  if (
    error instanceof PlaylistCapacityError ||
    error instanceof PlaylistInvalidOrderError
  )
    throw error;
  if (isRetryableConflict(error)) throw new PlaylistConflictError();
  throw new PlaylistDatabaseError('No se pudo acceder a playlists', {
    cause: error,
  });
}

export class PrismaPlaylistRepository implements PlaylistRepository {
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

  async listOwned(ownerId: string): Promise<PlaylistSummary[]> {
    try {
      return (
        await getDatabase().playlist.findMany({
          where: { userId: ownerId },
          orderBy: [{ updatedAt: 'desc' }, { id: 'asc' }],
          include: detailInclude,
        })
      ).map(summary);
    } catch (error) {
      translate(error);
    }
  }

  async findAccessible(ownerId: string, playlistId: string) {
    try {
      const value = await getDatabase().playlist.findFirst({
        where: {
          id: playlistId,
          OR: [{ userId: ownerId }, { visibility: DatabaseVisibility.PUBLIC }],
        },
        include: detailInclude,
      });
      return value ? detail(value, ownerId) : null;
    } catch (error) {
      translate(error);
    }
  }

  async create(ownerId: string, input: PlaylistInput) {
    try {
      const value = await getDatabase().playlist.create({
        data: {
          userId: ownerId,
          name: input.name,
          description: input.description,
          visibility: databaseVisibility(input.visibility),
        },
        include: detailInclude,
      });
      return detail(value, ownerId);
    } catch (error) {
      translate(error);
    }
  }

  async updateOwned(
    ownerId: string,
    playlistId: string,
    input: PlaylistUpdate,
  ) {
    try {
      const found = await getDatabase().playlist.findFirst({
        where: { id: playlistId, userId: ownerId },
        select: { id: true },
      });
      if (!found) return null;
      const value = await getDatabase().playlist.update({
        where: { id: found.id },
        data: {
          ...(input.name !== undefined ? { name: input.name } : {}),
          ...(input.description !== undefined
            ? { description: input.description }
            : {}),
          ...(input.visibility !== undefined
            ? { visibility: databaseVisibility(input.visibility) }
            : {}),
        },
        include: detailInclude,
      });
      return detail(value, ownerId);
    } catch (error) {
      translate(error);
    }
  }

  async deleteOwned(ownerId: string, playlistId: string): Promise<boolean> {
    try {
      return (
        (
          await getDatabase().playlist.deleteMany({
            where: { id: playlistId, userId: ownerId },
          })
        ).count === 1
      );
    } catch (error) {
      translate(error);
    }
  }

  async addTrackOwned(
    ownerId: string,
    playlistId: string,
    track: Track,
    maximumItems: number,
  ) {
    try {
      return await getDatabase().$transaction(
        async (transaction) => {
          const playlist = await transaction.playlist.findFirst({
            where: { id: playlistId, userId: ownerId },
            select: { id: true },
          });
          if (!playlist) return null;
          const count = await transaction.playlistTrack.count({
            where: { playlistId },
          });
          if (count >= maximumItems) throw new PlaylistCapacityError();
          const storedTrack = await transaction.track.upsert({
            where: {
              source_sourceId: {
                source: track.source,
                sourceId: track.sourceId,
              },
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
          await transaction.playlistTrack.create({
            data: {
              playlistId,
              trackId: storedTrack.id,
              position: count,
            },
          });
          return detail(
            await transaction.playlist.update({
              where: { id: playlistId },
              data: { updatedAt: new Date() },
              include: detailInclude,
            }),
            ownerId,
          );
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      translate(error);
    }
  }

  async removeTrackOwned(ownerId: string, playlistId: string, itemId: string) {
    try {
      return await getDatabase().$transaction(
        async (transaction) => {
          const playlist = await transaction.playlist.findFirst({
            where: { id: playlistId, userId: ownerId },
            select: { id: true },
          });
          if (!playlist) return null;
          const item = await transaction.playlistTrack.findFirst({
            where: { id: itemId, playlistId },
            select: { position: true },
          });
          if (!item) return null;
          await transaction.playlistTrack.delete({ where: { id: itemId } });
          await transaction.playlistTrack.updateMany({
            where: { playlistId, position: { gt: item.position } },
            data: { position: { increment: 1000 } },
          });
          await transaction.playlistTrack.updateMany({
            where: { playlistId, position: { gt: item.position + 1000 } },
            data: { position: { decrement: 1001 } },
          });
          return detail(
            await transaction.playlist.update({
              where: { id: playlistId },
              data: { updatedAt: new Date() },
              include: detailInclude,
            }),
            ownerId,
          );
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      translate(error);
    }
  }

  async reorderOwned(
    ownerId: string,
    playlistId: string,
    itemIds: readonly string[],
  ) {
    try {
      return await getDatabase().$transaction(
        async (transaction) => {
          const playlist = await transaction.playlist.findFirst({
            where: { id: playlistId, userId: ownerId },
            select: { id: true },
          });
          if (!playlist) return null;
          const current = await transaction.playlistTrack.findMany({
            where: { playlistId },
            select: { id: true },
          });
          const currentIds = new Set(current.map((item) => item.id));
          if (
            currentIds.size !== itemIds.length ||
            new Set(itemIds).size !== itemIds.length ||
            itemIds.some((id) => !currentIds.has(id))
          )
            throw new PlaylistInvalidOrderError();
          await transaction.playlistTrack.updateMany({
            where: { playlistId },
            data: { position: { increment: 1000 } },
          });
          for (const [position, id] of itemIds.entries()) {
            await transaction.playlistTrack.update({
              where: { id },
              data: { position },
            });
          }
          return detail(
            await transaction.playlist.update({
              where: { id: playlistId },
              data: { updatedAt: new Date() },
              include: detailInclude,
            }),
            ownerId,
          );
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      translate(error);
    }
  }
}
