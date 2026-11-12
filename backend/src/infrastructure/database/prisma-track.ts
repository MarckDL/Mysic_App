import type { Prisma } from '../../generated/prisma/client.js';
import type { Track } from '../../modules/catalog/domain/music-provider.js';

export function catalogTrack(value: {
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

export function upsertTrack(
  transaction: Prisma.TransactionClient,
  track: Track,
) {
  return transaction.track.upsert({
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
}
