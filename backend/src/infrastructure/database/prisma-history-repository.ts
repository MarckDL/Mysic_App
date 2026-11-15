import { getDatabase } from './prisma.js';
import {
  HistoryConflict,
  type HistoryInput,
  type HistoryRepository,
} from '../../modules/history/domain/history.js';
import type { Track } from '../../modules/catalog/domain/music-provider.js';
export class PrismaHistoryRepository implements HistoryRepository {
  async owner(firebaseUid: string) {
    return (
      (
        await getDatabase().user.findUnique({
          where: { firebaseUid },
          select: { id: true },
        })
      )?.id ?? null
    );
  }
  async save(owner: string, input: HistoryInput, track: Track) {
    await getDatabase().$transaction(async (tx) => {
      // Empty-update Prisma upserts can race on the first catalog insertion.
      // Let PostgreSQL arbitrate the unique key in a single statement, keeping
      // the stored metadata unchanged when another request already created it.
      const [stored] = await tx.$queryRaw<{ id: string }[]>`
        INSERT INTO mysic.tracks
          (id, source, source_id, title, artist_name, duration_seconds, thumbnail_url)
        VALUES
          (gen_random_uuid(), ${track.source}, ${track.sourceId}, ${track.title},
           ${track.artistName}, ${track.durationSeconds}, ${track.thumbnailUrl})
        ON CONFLICT (source, source_id) DO UPDATE SET id = tracks.id
        RETURNING id
      `;
      if (!stored) throw new Error('Track insertion returned no identity');
      const count =
        await tx.$executeRaw`INSERT INTO mysic.listening_history (id,user_id,track_id,playback_session_id,started_at,listened_ms,completed) VALUES (gen_random_uuid(),${owner}::uuid,${stored.id}::uuid,${input.sessionId}::uuid,${new Date(input.startedAt)},${BigInt(input.listenedMs)},${input.completed}) ON CONFLICT (playback_session_id) DO UPDATE SET listened_ms=GREATEST(listening_history.listened_ms,EXCLUDED.listened_ms), completed=listening_history.completed OR EXCLUDED.completed WHERE listening_history.user_id=EXCLUDED.user_id AND listening_history.track_id=EXCLUDED.track_id AND listening_history.started_at=EXCLUDED.started_at`;
      if (!count) throw new HistoryConflict();
    });
  }
  async list(
    owner: string,
    limit: number,
    cursor?: { startedAt: string; id: string },
  ) {
    const rows = await getDatabase().listeningHistory.findMany({
      where: {
        userId: owner,
        ...(cursor
          ? {
              OR: [
                { startedAt: { lt: new Date(cursor.startedAt) } },
                {
                  startedAt: new Date(cursor.startedAt),
                  id: { lt: cursor.id },
                },
              ],
            }
          : {}),
      },
      orderBy: [{ startedAt: 'desc' }, { id: 'desc' }],
      take: limit,
      include: { track: true },
    });
    return rows.map((r) => ({
      id: r.id,
      startedAt: r.startedAt.toISOString(),
      listenedMs: Number(r.listenedMs),
      completed: r.completed,
      track: {
        ...r.track,
        id: `${r.track.source}:${r.track.sourceId}`,
        source: r.track.source as Track['source'],
      },
    }));
  }
}
