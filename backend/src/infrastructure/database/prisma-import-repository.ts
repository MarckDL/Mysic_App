import type { Prisma } from '../../generated/prisma/client.js';
import {
  ImportError,
  requireDraft,
  type ImportInput,
  type ImportItem,
  type ImportRepository,
  type MusicImport,
} from '../../modules/imports/domain/music-import.js';
import { getDatabase } from './prisma.js';

type StoredImport = Omit<MusicImport, 'items'> & { items: unknown };

function draft(row: StoredImport): MusicImport {
  return { ...row, items: row.items as ImportItem[] };
}

function json(items: ImportItem[]): Prisma.InputJsonValue {
  return JSON.parse(JSON.stringify(items)) as Prisma.InputJsonValue;
}

export class PrismaImportRepository implements ImportRepository {
  async findUserId(firebaseUid: string) {
    const user = await getDatabase().user.findUnique({
      where: { firebaseUid },
      select: { id: true },
    });
    return user?.id ?? null;
  }

  private async purge() {
    await getDatabase().musicImport.deleteMany({
      where: { confirmedAt: null, expiresAt: { lte: new Date() } },
    });
  }

  async prepare(userId: string, input: ImportInput, fingerprint: string) {
    await this.purge();
    return getDatabase().$transaction(async (tx) => {
      // Serializes creation per owner, including the active draft limit.
      await tx.$queryRaw`SELECT id FROM mysic.users WHERE id = ${userId}::uuid FOR UPDATE`;
      const existing = await tx.musicImport.findUnique({
        where: { id: input.id },
      });
      if (existing) {
        if (existing.userId !== userId)
          throw new ImportError(
            404,
            'IMPORT_NOT_FOUND',
            'Importación no encontrada',
          );
        if (existing.fingerprint !== fingerprint)
          throw new ImportError(
            409,
            'IMPORT_CONFLICT',
            'La importación tiene otro contenido',
          );
        return requireDraft(draft(existing));
      }
      const count = await tx.musicImport.count({
        where: { userId, confirmedAt: null },
      });
      if (count >= 20)
        throw new ImportError(
          429,
          'IMPORT_LIMIT',
          'Continúa una importación pendiente o espera a que caduque',
        );
      return draft(
        await tx.musicImport.create({
          data: {
            id: input.id,
            userId,
            fingerprint,
            name: input.name,
            items: json(
              input.sourceIds.map((sourceId) => ({
                sourceId,
                status: 'pending',
              })),
            ),
            expiresAt: new Date(Date.now() + 24 * 60 * 60_000),
          },
        }),
      );
    });
  }

  async list(userId: string) {
    await this.purge();
    const rows = await getDatabase().musicImport.findMany({
      where: { userId, confirmedAt: null },
      orderBy: { expiresAt: 'desc' },
      take: 20,
    });
    return rows.map(draft);
  }

  async find(userId: string, id: string) {
    const row = await getDatabase().musicImport.findFirst({
      where: { id, userId },
    });
    return row ? draft(row) : null;
  }

  private async locked<T>(
    userId: string,
    id: string,
    operation: (tx: Prisma.TransactionClient, value: MusicImport) => Promise<T>,
  ) {
    return getDatabase().$transaction(
      async (tx) => {
        await tx.$queryRaw`SELECT id FROM mysic.music_imports WHERE id = ${id}::uuid AND user_id = ${userId}::uuid FOR UPDATE`;
        const row = await tx.musicImport.findFirst({ where: { id, userId } });
        return operation(tx, requireDraft(row ? draft(row) : null));
      },
      { timeout: 20_000 },
    );
  }

  async merge(
    userId: string,
    id: string,
    updates: { index: number; item: ImportItem }[],
  ) {
    return this.locked(userId, id, async (tx, value) => {
      if (value.confirmedAt) return value;
      for (const { index, item } of updates) {
        const current = value.items[index];
        // A delayed transient failure must not overwrite a successful resolution.
        if (
          current &&
          current.sourceId === item.sourceId &&
          current.status !== 'ready' &&
          current.status !== 'unavailable'
        ) {
          value.items[index] = item;
        }
      }
      return draft(
        await tx.musicImport.update({
          where: { id },
          data: { items: json(value.items) },
        }),
      );
    });
  }

  async confirm(userId: string, id: string) {
    return this.locked(userId, id, async (tx, value) => {
      if (value.confirmedAt) return value;
      if (value.items.some((item) => item.status === 'pending')) {
        throw new ImportError(
          409,
          'IMPORT_PENDING',
          'Espera a que termine la revisión',
        );
      }
      const tracks = value.items.flatMap((item) =>
        item.status === 'ready' && item.track ? [item.track] : [],
      );
      if (!tracks.length)
        throw new ImportError(
          409,
          'IMPORT_EMPTY',
          'No hay canciones reconocidas para guardar',
        );
      const playlist = await tx.playlist.create({
        data: { userId, name: value.name, visibility: 'PRIVATE' },
      });
      // Keep confirmation bounded to a handful of database round trips.
      // Existing canonical tracks retain their current metadata.
      const unique = [
        ...new Map(tracks.map((track) => [track.sourceId, track])).values(),
      ];
      await tx.track.createMany({
        data: unique.map((track) => ({
          source: 'youtube',
          sourceId: track.sourceId,
          title: track.title,
          artistName: track.artistName,
          durationSeconds: track.durationSeconds,
          thumbnailUrl: track.thumbnailUrl,
        })),
        skipDuplicates: true,
      });
      const stored = await tx.track.findMany({
        where: {
          source: 'youtube',
          sourceId: { in: unique.map((track) => track.sourceId) },
        },
        select: { id: true, sourceId: true },
      });
      const ids = new Map(stored.map((track) => [track.sourceId, track.id]));
      await tx.playlistTrack.createMany({
        data: tracks.map((track, position) => ({
          playlistId: playlist.id,
          trackId: ids.get(track.sourceId)!,
          position,
        })),
      });
      return draft(
        await tx.musicImport.update({
          where: { id },
          data: {
            confirmedAt: new Date(),
            playlistId: playlist.id,
            savedCount: tracks.length,
            skippedCount: value.items.length - tracks.length,
            items: [],
          },
        }),
      );
    });
  }

  async discard(userId: string, id: string) {
    await this.locked(userId, id, async (tx, value) => {
      if (value.confirmedAt) {
        throw new ImportError(
          409,
          'IMPORT_CONFIRMED',
          'La importación ya fue confirmada',
        );
      }
      await tx.musicImport.delete({ where: { id } });
    });
  }
}
