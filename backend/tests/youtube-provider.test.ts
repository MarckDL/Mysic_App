import type { Innertube } from 'youtubei.js';
import { describe, expect, it, vi } from 'vitest';
import { YoutubeProvider } from '../src/infrastructure/music/youtube-provider.js';
import {
  ProviderTimeoutError,
  ProviderUnavailableError,
} from '../src/modules/catalog/domain/music-provider.js';

function fixture() {
  const search = vi.fn().mockResolvedValue({
    contents: {
      length: 1,
      filterType: () => [
        { contents: [{ item_type: 'song', id: 'abcdefghijk', title: 'Song' }] },
      ],
    },
  });
  const getInfo = vi.fn().mockResolvedValue({
    basic_info: { id: 'abcdefghijk', title: 'Song', author: 'Artist' },
    playability_status: { status: 'UNPLAYABLE' },
  });
  const create = vi.fn(
    async () => ({ music: { search, getInfo } }) as unknown as Innertube,
  );
  return { provider: new YoutubeProvider(create), search, getInfo, create };
}

describe('adaptador YoutubeProvider', () => {
  it('filtra canciones y solo devuelve el contrato propio', async () => {
    const { provider, search } = fixture();
    const tracks = await provider.search('artist');
    expect(search).toHaveBeenCalledWith('artist', { type: 'song' });
    expect(tracks[0]).toMatchObject({
      id: 'youtube:abcdefghijk',
      source: 'youtube',
      title: 'Song',
    });
  });
  it('consulta detalle independiente y no afirma reproducción con UNPLAYABLE', async () => {
    const { provider, getInfo, search } = fixture();
    expect((await provider.getTrack('abcdefghijk'))?.title).toBe('Song');
    expect(getInfo).toHaveBeenCalledWith('abcdefghijk');
    expect(search).not.toHaveBeenCalled();
    expect((await provider.resolvePlayback()).mode).toBe('unavailable');
  });
  it('rechaza respuestas malformadas sin convertirlas en vacíos válidos', async () => {
    const { provider, search } = fixture();
    search.mockResolvedValueOnce({});
    await expect(provider.search('q')).rejects.toBeInstanceOf(
      ProviderUnavailableError,
    );
  });
  it('controla restricciones externas y descarta detalles de otra pista', async () => {
    const { provider, getInfo } = fixture();
    getInfo.mockRejectedValueOnce(new Error('login required - private data'));
    await expect(provider.getTrack('abcdefghijk')).rejects.toBeInstanceOf(
      ProviderUnavailableError,
    );
    getInfo.mockResolvedValueOnce({
      basic_info: { id: '12345678901', title: 'Other' },
    });
    await expect(provider.getTrack('abcdefghijk')).rejects.toBeInstanceOf(
      ProviderUnavailableError,
    );
  });
  it('respeta abort y no hace peticiones con URLs arbitrarias', async () => {
    const { provider, create } = fixture();
    const controller = new AbortController();
    controller.abort();
    await expect(
      provider.search('q', controller.signal),
    ).rejects.toBeInstanceOf(ProviderTimeoutError);
    await expect(provider.getTrack('https://evil.test')).rejects.toBeInstanceOf(
      ProviderUnavailableError,
    );
    expect(create).not.toHaveBeenCalled();
  });
});
