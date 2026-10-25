import process from 'node:process';
import console from 'node:console';
import {
  normalizeYoutubeSongs,
  normalizeYoutubeDetail,
} from '../src/infrastructure/music/youtube-normalizer.ts';

// Solo metadatos. Ejecutar mediante pnpm catalog:check (tsx).
let stage = 'dependency';
try {
  const { Innertube, YTNodes, Log } = await import('youtubei.js');
  Log.setLevel(Log.Level.NONE);
  stage = 'session';
  const yt = await Innertube.create({
    lang: 'en',
    location: 'PE',
    retrieve_player: false,
    enable_session_cache: false,
    fast_fail: true,
    fetch: (input, init) =>
      globalThis.fetch(input, {
        ...init,
        signal: globalThis.AbortSignal.any([
          globalThis.AbortSignal.timeout(10_000),
          ...(init?.signal ? [init.signal] : []),
        ]),
      }),
  });
  stage = 'search';
  const result = await yt.music.search('Daft Punk Get Lucky', { type: 'song' });
  const songs =
    result.contents
      ?.filterType(YTNodes.MusicShelf)
      .flatMap((shelf) => shelf.contents) ?? [];
  const tracks = normalizeYoutubeSongs(songs);
  console.info(JSON.stringify({ stage, normalizedTracks: tracks.length }));
  if (!tracks.length) throw new Error('No usable metadata');
  stage = 'detail';
  const first = tracks[0];
  const info = await yt.music.getInfo(first.sourceId);
  const detail = normalizeYoutubeDetail(info.basic_info);
  if (!detail || detail.sourceId !== first.sourceId)
    throw new Error('Invalid detail');
  console.info(
    JSON.stringify({
      stage,
      metadataConfirmed: true,
      title: detail.title,
      artistName: detail.artistName,
      // No interpretar este resultado como disponibilidad de audio.
      audioAvailabilityVerified: false,
    }),
  );
} catch (error) {
  const missing = error?.code === 'ERR_MODULE_NOT_FOUND';
  console.error(
    JSON.stringify({
      stage,
      success: false,
      reason: missing
        ? 'Dependencia no instalada: ejecutar pnpm add youtubei.js@18.3.0 en backend'
        : 'No se pudo confirmar el proveedor. No se han descargado audio ni credenciales.',
    }),
  );
  process.exitCode = 1;
}
