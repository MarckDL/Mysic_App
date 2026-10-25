import process from 'node:process';
import console from 'node:console';
import { YoutubeProvider } from '../src/infrastructure/music/youtube-provider.ts';
import { CatalogService } from '../src/modules/catalog/application/catalog-service.ts';

// Usa el mismo adaptador, normalizador, caché y timeout de la API; solo metadatos.
let stage = 'search';
try {
  const catalog = new CatalogService(new YoutubeProvider());
  const tracks = await catalog.search('Daft Punk Get Lucky');
  console.info(JSON.stringify({ stage, normalizedTracks: tracks.length }));
  if (!tracks.length) throw new Error('No usable metadata');
  stage = 'detail';
  const first = tracks[0];
  const detail = await catalog.getTrack(first.sourceId);
  if (!detail || detail.sourceId !== first.sourceId)
    throw new Error('Invalid detail');
  console.info(
    JSON.stringify({
      stage,
      metadataConfirmed: true,
      title: detail.title,
      artistName: detail.artistName,
      audioAvailabilityVerified: false,
    }),
  );
} catch {
  console.error(
    JSON.stringify({
      stage,
      success: false,
      reason:
        'No se pudo confirmar el proveedor. No se han descargado audio ni credenciales.',
    }),
  );
  process.exitCode = 1;
}
