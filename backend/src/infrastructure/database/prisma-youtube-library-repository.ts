import type { Track } from '../../modules/catalog/domain/music-provider.js';
import {
  YoutubeLibraryDatabaseError,
  type YoutubeConnectionStatus,
  type YoutubeLibrarySnapshot,
} from '../../modules/youtube-library/domain/youtube-library.js';
import type {
  YoutubeLibraryRepository,
  YoutubeLibraryView,
} from '../../modules/youtube-library/domain/youtube-library-repository.js';
import { getDatabase } from './prisma.js';

function outputTrack(value: {
  source: string;
  sourceId: string;
  title: string;
  artistName: string;
  durationSeconds: number | null;
  thumbnailUrl: string | null;
}): Track {
  return {
    id: `${value.source}:${value.sourceId}`,
    source: value.source as Track['source'],
    sourceId: value.sourceId,
    title: value.title,
    artistName: value.artistName,
    durationSeconds: value.durationSeconds,
    thumbnailUrl: value.thumbnailUrl,
  };
}

function fail(error: unknown): never {
  throw new YoutubeLibraryDatabaseError(
    'No se pudo acceder a la biblioteca de YouTube',
    { cause: error },
  );
}

export class PrismaYoutubeLibraryRepository implements YoutubeLibraryRepository {
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
      fail(error);
    }
  }

  async status(ownerId: string): Promise<YoutubeConnectionStatus> {
    try {
      const value = await getDatabase().youtubeConnection.findUnique({
        where: { userId: ownerId },
        include: {
          _count: {
            select: { playlists: true, likes: true, subscriptions: true },
          },
        },
      });
      return value
        ? {
            connected: true,
            displayName: value.displayName,
            avatarUrl: value.avatarUrl,
            lastSyncedAt: value.lastSyncedAt.toISOString(),
            playlistCount: value._count.playlists,
            likedTrackCount: value._count.likes,
            subscriptionCount: value._count.subscriptions,
          }
        : {
            connected: false,
            displayName: null,
            avatarUrl: null,
            lastSyncedAt: null,
            playlistCount: 0,
            likedTrackCount: 0,
            subscriptionCount: 0,
          };
    } catch (error) {
      fail(error);
    }
  }

  async library(ownerId: string): Promise<YoutubeLibraryView> {
    try {
      const value = await getDatabase().youtubeConnection.findUnique({
        where: { userId: ownerId },
        include: {
          likes: { include: { track: true } },
          playlists: { orderBy: { title: 'asc' } },
          subscriptions: { orderBy: { title: 'asc' } },
        },
      });
      if (!value) return { likes: [], playlists: [], subscriptions: [] };
      return {
        likes: value.likes.map((item) => ({
          ...outputTrack(item.track),
          origin: 'youtube' as const,
          readOnly: true as const,
        })),
        playlists: value.playlists.map((item) => ({
          id: item.id,
          externalId: item.externalId,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
          itemCount: item.itemCount,
          origin: 'youtube' as const,
          readOnly: true as const,
        })),
        subscriptions: value.subscriptions.map((item) => ({
          channelId: item.channelId,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
        })),
      };
    } catch (error) {
      fail(error);
    }
  }

  async replace(
    ownerId: string,
    snapshot: YoutubeLibrarySnapshot,
  ): Promise<YoutubeConnectionStatus> {
    try {
      const syncedAt = new Date();
      await getDatabase().$transaction(async (database) => {
        await database.youtubeConnection.upsert({
          where: { userId: ownerId },
          create: {
            userId: ownerId,
            channelId: snapshot.channel.id,
            displayName: snapshot.channel.displayName,
            avatarUrl: snapshot.channel.avatarUrl,
            lastSyncedAt: syncedAt,
          },
          update: {
            channelId: snapshot.channel.id,
            displayName: snapshot.channel.displayName,
            avatarUrl: snapshot.channel.avatarUrl,
            lastSyncedAt: syncedAt,
          },
        });
        await database.youtubeRemotePlaylist.deleteMany({
          where: { userId: ownerId },
        });
        await database.youtubeRemoteLike.deleteMany({
          where: { userId: ownerId },
        });
        await database.youtubeRemoteSubscription.deleteMany({
          where: { userId: ownerId },
        });

        const stored = new Map<string, string>();
        const putTrack = async (value: Track) => {
          const key = `${value.source}:${value.sourceId}`;
          const cached = stored.get(key);
          if (cached) return cached;
          const result = await database.track.upsert({
            where: {
              source_sourceId: {
                source: value.source,
                sourceId: value.sourceId,
              },
            },
            create: {
              source: value.source,
              sourceId: value.sourceId,
              title: value.title,
              artistName: value.artistName,
              durationSeconds: value.durationSeconds,
              thumbnailUrl: value.thumbnailUrl,
            },
            update: {
              title: value.title,
              artistName: value.artistName,
              durationSeconds: value.durationSeconds,
              thumbnailUrl: value.thumbnailUrl,
              metadataUpdatedAt: syncedAt,
            },
            select: { id: true },
          });
          stored.set(key, result.id);
          return result.id;
        };

        for (const playlist of snapshot.playlists) {
          const remote = await database.youtubeRemotePlaylist.create({
            data: {
              userId: ownerId,
              externalId: playlist.externalId,
              title: playlist.title,
              thumbnailUrl: playlist.thumbnailUrl,
              itemCount: playlist.tracks.length,
            },
            select: { id: true },
          });
          for (const item of playlist.tracks) {
            await database.youtubeRemotePlaylistTrack.create({
              data: {
                playlistId: remote.id,
                trackId: await putTrack(item),
                externalItemId: item.externalItemId,
                position: item.position,
              },
            });
          }
        }
        for (const value of snapshot.likes) {
          await database.youtubeRemoteLike.create({
            data: { userId: ownerId, trackId: await putTrack(value) },
          });
        }
        if (snapshot.subscriptions.length) {
          await database.youtubeRemoteSubscription.createMany({
            data: snapshot.subscriptions.map((value) => ({
              userId: ownerId,
              ...value,
            })),
          });
        }
      });
      return {
        connected: true,
        displayName: snapshot.channel.displayName,
        avatarUrl: snapshot.channel.avatarUrl,
        lastSyncedAt: syncedAt.toISOString(),
        playlistCount: snapshot.playlists.length,
        likedTrackCount: snapshot.likes.length,
        subscriptionCount: snapshot.subscriptions.length,
      };
    } catch (error) {
      fail(error);
    }
  }

  async duplicate(ownerId: string, remotePlaylistId: string) {
    try {
      return await getDatabase().$transaction(async (database) => {
        const remote = await database.youtubeRemotePlaylist.findFirst({
          where: { id: remotePlaylistId, userId: ownerId },
          include: { tracks: { orderBy: { position: 'asc' } } },
        });
        if (!remote) return null;
        const created = await database.playlist.create({
          data: {
            userId: ownerId,
            name: remote.title.slice(0, 150),
            description: 'Duplicada desde YouTube',
            tracks: {
              create: remote.tracks.map((item, position) => ({
                trackId: item.trackId,
                position,
              })),
            },
          },
          include: { _count: { select: { tracks: true } } },
        });
        return {
          id: created.id,
          name: created.name,
          description: created.description,
          visibility: 'private' as const,
          trackCount: created._count.tracks,
          createdAt: created.createdAt.toISOString(),
          updatedAt: created.updatedAt.toISOString(),
          origin: 'mysic' as const,
          readOnly: false as const,
        };
      });
    } catch (error) {
      fail(error);
    }
  }

  async disconnect(ownerId: string) {
    try {
      return (
        (
          await getDatabase().youtubeConnection.deleteMany({
            where: { userId: ownerId },
          })
        ).count === 1
      );
    } catch (error) {
      fail(error);
    }
  }
}
