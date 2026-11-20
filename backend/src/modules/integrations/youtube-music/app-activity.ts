import { getDatabase } from '../../../infrastructure/database/prisma.js';
import { LinkError } from '../youtube/domain.js';
import type { MusicListen } from './provider.js';

const retained = 600;
const month = 30 * 24 * 60 * 60 * 1000;

export async function findAppListen(
  userId: string,
  generation: string,
  listenId: string,
) {
  const value = await getDatabase().channelMusicListen.findUnique({
    where: { userId_generation_listenId: { userId, generation, listenId } },
    select: { videoId: true, listenedMs: true },
  });
  return value
    ? { trackId: value.videoId, listenedMs: value.listenedMs }
    : null;
}

export async function storeAppListen(
  userId: string,
  generation: string,
  listenId: string,
  listen: MusicListen,
) {
  await getDatabase().$transaction(async (db) => {
    // Serialize only this channel's writes against replacement, revocation and another device.
    const rows = await db.$queryRaw<
      {
        generation: string;
        mysicHistoryPaused: boolean;
        mysicActivityEpoch: number;
      }[]
    >`
      SELECT "generation","mysicHistoryPaused","mysicActivityEpoch" FROM "mysic"."external_music_connections"
      WHERE "userId" = ${userId}::uuid AND "generation" = ${generation}::uuid
        AND "status" = 'linked' FOR UPDATE`;
    if (!rows.length) throw new LinkError(409, 'MUSIC_LINK_CHANGED');
    if (rows[0]?.mysicHistoryPaused)
      throw new LinkError(409, 'MYSIC_HISTORY_PAUSED');
    if (rows[0]!.mysicActivityEpoch !== listen.activityEpoch)
      throw new LinkError(409, 'MYSIC_ACTIVITY_CHANGED');
    const key = { userId, generation, listenId };
    const current = await db.channelMusicListen.upsert({
      where: { userId_generation_listenId: key },
      update: {},
      create: {
        ...key,
        videoId: listen.trackId,
        listenedMs: listen.listenedMs,
      },
      select: { videoId: true },
    });
    if (current.videoId !== listen.trackId)
      throw new LinkError(409, 'MUSIC_LISTEN_CONFLICT');
    const old = await db.channelMusicListen.findMany({
      where: { userId, generation },
      orderBy: [{ playedAt: 'desc' }, { listenId: 'desc' }],
      skip: retained,
      select: { listenId: true },
    });
    if (old.length)
      await db.channelMusicListen.deleteMany({
        where: {
          userId,
          generation,
          listenId: { in: old.map((v) => v.listenId) },
        },
      });
  });
}

type Event = { listenId: string; videoId: string; playedAt: Date };
export async function appActivityPage(
  userId: string,
  generation: string,
  repeats: boolean,
  size: number,
  token?: string,
) {
  // The token is decrypted and authenticated by LibraryCursors before it reaches this function.
  const [stamp, offset] = token
    ? (token.split('/').map(Number) as [number, number])
    : [Date.now(), 0];
  const records = await getDatabase().channelMusicListen.findMany({
    where: {
      userId,
      generation,
      playedAt: {
        lte: new Date(stamp),
        ...(repeats && { gte: new Date(stamp - month) }),
      },
    },
    select: { listenId: true, videoId: true, playedAt: true },
    orderBy: [{ playedAt: 'desc' }, { listenId: 'desc' }],
    take: retained,
  });
  const plays: { event: Event; count: number }[] = [];
  const counts = new Map<string, { event: Event; count: number }>();
  let last: Event | undefined;
  for (const event of records.reverse()) {
    if (
      last?.videoId === event.videoId &&
      event.playedAt.getTime() - last.playedAt.getTime() < 30_000
    )
      continue;
    last = event;
    plays.push({ event, count: 1 });
    counts.set(event.videoId, {
      event,
      count: (counts.get(event.videoId)?.count ?? 0) + 1,
    });
  }
  const sorted = repeats
    ? [...counts.values()]
        .filter((v) => v.count >= 2)
        .sort(
          (a, b) =>
            b.count - a.count ||
            b.event.playedAt.getTime() - a.event.playedAt.getTime() ||
            b.event.listenId.localeCompare(a.event.listenId),
        )
        .slice(0, 50)
    : plays.reverse();
  return {
    rows: sorted.slice(offset, offset + size),
    nextPageToken:
      offset + size < sorted.length ? stamp + '/' + (offset + size) : undefined,
  };
}

export async function updateAppActivity(
  userId: string,
  generation: string,
  action: 'clear' | boolean,
) {
  await getDatabase().$transaction(async (db) => {
    const rows = await db.$queryRaw<
      { generation: string; mysicHistoryPaused: boolean }[]
    >`
      SELECT "generation","mysicHistoryPaused" FROM "mysic"."external_music_connections"
      WHERE "userId"=${userId}::uuid AND "generation"=${generation}::uuid AND "status"='linked' FOR UPDATE`;
    if (!rows.length) throw new LinkError(409, 'MUSIC_LINK_CHANGED');
    if (action === rows[0]!.mysicHistoryPaused) return;
    if (action === 'clear') {
      await db.channelMusicListen.deleteMany({ where: { userId, generation } });
    }
    await db.externalMusicConnection.update({
      where: { userId },
      data: {
        mysicActivityEpoch: { increment: 1 },
        ...(action !== 'clear' && { mysicHistoryPaused: action }),
      },
    });
  });
}
