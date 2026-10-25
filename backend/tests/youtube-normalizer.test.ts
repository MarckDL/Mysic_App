import { describe, expect, it } from 'vitest';
import {
  normalizeYoutubeDetail,
  normalizeYoutubeSong,
  normalizeYoutubeSongs,
} from '../src/infrastructure/music/youtube-normalizer.js';

const song = {
  id: 'abcdefghijk',
  item_type: 'song',
  title: '  Canción de prueba  ',
  artists: [{ name: 'Artista A' }, { name: 'Artista B' }],
  duration: { seconds: 215 },
  thumbnails: [{ url: 'https://i.ytimg.com/vi/abcdefghijk/default.jpg' }],
  privateField: 'never-return-this',
};

describe('normalización del catálogo YouTube', () => {
  it('devuelve exclusivamente el DTO Mysic', () => {
    expect(normalizeYoutubeSong(song)).toEqual({
      id: 'youtube:abcdefghijk',
      source: 'youtube',
      sourceId: 'abcdefghijk',
      title: 'Canción de prueba',
      artistName: 'Artista A, Artista B',
      durationSeconds: 215,
      thumbnailUrl: song.thumbnails[0]?.url,
    });
  });
  it.each(['video', 'playlist', 'album', 'artist', 'unknown'])(
    'descarta %s',
    (item_type) => {
      expect(normalizeYoutubeSong({ ...song, item_type })).toBeNull();
    },
  );
  it('maneja datos faltantes sin inventar título ni duración', () => {
    expect(normalizeYoutubeSong({ ...song, title: undefined })).toBeNull();
    expect(
      normalizeYoutubeSong({
        ...song,
        artists: null,
        duration: null,
        thumbnails: null,
      }),
    ).toMatchObject({
      artistName: 'Artista no disponible',
      durationSeconds: null,
      thumbnailUrl: null,
    });
    expect(normalizeYoutubeSong(null)).toBeNull();
  });
  it('rechaza IDs y miniaturas fuera del proveedor', () => {
    expect(
      normalizeYoutubeSong({ ...song, id: 'https://example.test' }),
    ).toBeNull();
    for (const url of [
      'http://i.ytimg.com/a',
      'https://evil.test/a',
      'https://i.ytimg.com.evil.test/a',
    ]) {
      expect(
        normalizeYoutubeSong({ ...song, thumbnails: [{ url }] })?.thumbnailUrl,
      ).toBeNull();
    }
  });
  it('deduplica y limita sin alterar el orden', () => {
    expect(
      normalizeYoutubeSongs([song, song, { ...song, id: '12345678901' }]),
    ).toHaveLength(2);
    expect(
      normalizeYoutubeSongs([song, { ...song, id: '12345678901' }], 1)[0]
        ?.sourceId,
    ).toBe(song.id);
  });
  it('normaliza el detalle independientemente de una búsqueda anterior', () => {
    expect(
      normalizeYoutubeDetail({
        id: song.id,
        title: song.title,
        author: 'Artista',
        duration: 215,
        thumbnail: song.thumbnails,
      }),
    ).toMatchObject({
      id: `youtube:${song.id}`,
      artistName: 'Artista',
      durationSeconds: 215,
    });
    expect(
      normalizeYoutubeDetail({
        id: song.id,
        title: song.title,
        is_live: true,
        duration: 999,
      })?.durationSeconds,
    ).toBeNull();
  });
});
