import { Innertube, Log, YTNodes } from 'youtubei.js';
import { assessYoutubeAudio } from '../src/infrastructure/music/youtube-audio-assessment.js';
import { youtubeSourceIdPattern } from '../src/infrastructure/music/youtube-normalizer.js';

Log.setLevel(Log.Level.NONE);
const args = process.argv.slice(2).filter((arg) => arg !== '--');
if (args.length > 1 || (args[0] && !youtubeSourceIdPattern.test(args[0]))) {
  console.error('Uso: pnpm playback:probe [VIDEO_ID de 11 caracteres]');
  process.exitCode = 1;
} else {
  let stage = 'session';
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 25_000);
    try {
      const client = await Innertube.create({
        lang: 'en',
        location: 'PE',
        retrieve_player: true,
        enable_session_cache: false,
        fail_fast: true,
        fetch: (input, init) =>
          fetch(input, {
            ...init,
            signal: AbortSignal.any([
              controller.signal,
              AbortSignal.timeout(10_000),
              ...(init?.signal ? [init.signal] : []),
            ]),
          }),
      });
      console.info(
        JSON.stringify({
          stage: 'player-context',
          playerLoaded: Boolean(client.session.player),
          signatureTimestampPresent: Boolean(
            client.session.player?.signature_timestamp,
          ),
        }),
      );
      let sourceId = args[0];
      if (!sourceId) {
        stage = 'search';
        const results = await client.music.search('Daft Punk Get Lucky', {
          type: 'song',
        });
        sourceId = results.contents
          ?.filterType(YTNodes.MusicShelf)
          .flatMap((shelf) => shelf.contents)
          .find((item) => item.item_type === 'song')?.id;
      }
      if (!sourceId) throw new Error();
      stage = 'assessment';
      const info = await client.getBasicInfo(sourceId);
      console.info(JSON.stringify(assessYoutubeAudio(info, sourceId), null, 2));
    } finally {
      clearTimeout(timer);
    }
  } catch {
    console.error(
      JSON.stringify({
        stage,
        diagnosticCompleted: false,
        reason:
          'No se pudo consultar el proveedor. No se imprimen respuestas internas ni credenciales.',
      }),
    );
    process.exitCode = 1;
  }
}
