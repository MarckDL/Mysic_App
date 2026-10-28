import { Innertube, Log, YTNodes } from 'youtubei.js';
import {
  ProviderTimeoutError,
  ProviderUnavailableError,
  type MusicProvider,
  type Track,
} from '../../modules/catalog/domain/music-provider.js';
import {
  normalizeYoutubeDetail,
  normalizeYoutubeSongs,
  youtubeSourceIdPattern,
} from './youtube-normalizer.js';

// Los logs internos pueden contener respuestas completas del proveedor.
Log.setLevel(Log.Level.NONE);

async function createClient(signal?: AbortSignal) {
  return Innertube.create({
    lang: 'en',
    location: 'PE',
    retrieve_player: false,
    enable_session_cache: false,
    fail_fast: true,
    fetch: (input, init) =>
      fetch(input, {
        ...init,
        signal: AbortSignal.any([
          AbortSignal.timeout(10_000),
          ...(signal ? [signal] : []),
          ...(init?.signal ? [init.signal] : []),
        ]),
      }),
  });
}

type ClientFactory = typeof createClient;

export class YoutubeProvider implements MusicProvider {
  constructor(private readonly clientFactory: ClientFactory = createClient) {}

  private async execute<T>(
    signal: AbortSignal | undefined,
    action: (client: Awaited<ReturnType<ClientFactory>>) => Promise<T>,
  ): Promise<T> {
    try {
      signal?.throwIfAborted();
      const client = await this.clientFactory(signal);
      const result = await action(client);
      signal?.throwIfAborted();
      return result;
    } catch (error) {
      if (
        signal?.aborted ||
        (error instanceof Error &&
          ['TimeoutError', 'AbortError'].includes(error.name))
      ) {
        throw new ProviderTimeoutError();
      }
      throw new ProviderUnavailableError();
    }
  }

  search(query: string, signal?: AbortSignal): Promise<Track[]> {
    return this.execute(signal, async (client) => {
      const result = await client.music.search(query, { type: 'song' });
      if (!result.contents) throw new ProviderUnavailableError();
      const items = result.contents
        .filterType(YTNodes.MusicShelf)
        .flatMap((shelf) => shelf.contents);
      const songs = items.filter((item) => item.item_type === 'song');
      const tracks = normalizeYoutubeSongs(songs);
      if (songs.length > 0 && tracks.length === 0)
        throw new ProviderUnavailableError();
      // Sin shelf ni mensaje no podemos distinguir vacío de formato inesperado.
      if (items.length === 0 && result.contents.length === 0 && !result.message)
        throw new ProviderUnavailableError();
      return tracks;
    });
  }

  getTrack(sourceId: string, signal?: AbortSignal): Promise<Track | null> {
    if (!youtubeSourceIdPattern.test(sourceId))
      return Promise.reject(new ProviderUnavailableError());
    return this.execute(signal, async (client) => {
      const info = await client.music.getInfo(sourceId);
      const track = normalizeYoutubeDetail(info.basic_info);
      // Un estado de audio UNPLAYABLE no elimina metadatos válidos ni habilita audio.
      if (!track || track.sourceId !== sourceId)
        throw new ProviderUnavailableError();
      return track;
    });
  }

  async resolvePlayback() {
    return {
      mode: 'unavailable' as const,
      reason:
        'No hay una fuente de audio autorizada y compatible configurada para esta pista de YouTube.',
    };
  }
}
