import type { Track } from '../../catalog/domain/music-provider.js';

export interface ImportInput {
  id: string;
  name: string;
  sourceIds: string[];
}

export interface ImportItem {
  sourceId: string;
  status: 'pending' | 'ready' | 'unavailable' | 'retry';
  track?: Track;
}

export interface MusicImport {
  id: string;
  userId: string;
  fingerprint: string;
  name: string;
  items: ImportItem[];
  expiresAt: Date;
  confirmedAt: Date | null;
  playlistId: string | null;
  savedCount: number;
  skippedCount: number;
}

export class ImportError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export function requireDraft(value: MusicImport | null): MusicImport {
  if (!value || (!value.confirmedAt && value.expiresAt <= new Date())) {
    throw new ImportError(
      404,
      'IMPORT_NOT_FOUND',
      'Importación caducada o no encontrada',
    );
  }
  return value;
}

export function importView(value: MusicImport) {
  return {
    id: value.id,
    name: value.name,
    expiresAt: value.expiresAt.toISOString(),
    confirmed: value.confirmedAt !== null,
    playlistId: value.playlistId,
    savedCount: value.savedCount,
    skippedCount: value.skippedCount,
    items: value.items,
  };
}

export interface ImportRepository {
  findUserId(firebaseUid: string): Promise<string | null>;
  prepare(
    userId: string,
    input: ImportInput,
    fingerprint: string,
  ): Promise<MusicImport>;
  list(userId: string): Promise<MusicImport[]>;
  find(userId: string, id: string): Promise<MusicImport | null>;
  merge(
    userId: string,
    id: string,
    updates: { index: number; item: ImportItem }[],
  ): Promise<MusicImport>;
  confirm(userId: string, id: string): Promise<MusicImport>;
  discard(userId: string, id: string): Promise<void>;
}
