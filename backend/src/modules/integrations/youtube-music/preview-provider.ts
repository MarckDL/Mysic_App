import { LinkError } from '../youtube/domain.js';
import {
  musicSurfaces,
  type MusicListen,
  type MusicPageRequest,
  type MusicPlaylist,
  type MusicTrack,
  type YouTubeMusicProvider,
} from './provider.js';

function fixture(
  id: string,
  name: string,
  titles: [string, string, string],
  historyPaused = false,
) {
  const songs: MusicTrack[] = titles.map((title, index) => ({
    kind: 'track',
    id: id + '-track-' + (index + 1),
    title,
    artist: 'Mysic · audio de prueba',
    durationSeconds: 8,
    playback: 'bundledPreview',
  }));
  const playlist: MusicPlaylist = {
    kind: 'playlist',
    id: id + '-private',
    title: 'Playlist privada · ' + name,
    private: true,
  };
  const entries = [
    songs[0]!,
    { kind: 'video' },
    songs[1]!,
    { kind: 'unavailable' },
    songs[2]!,
  ];
  return { id, name, songs, playlist, entries, historyPaused };
}

export class PreviewMusicProvider implements YouTubeMusicProvider {
  readonly kind = 'preview';
  readonly capabilities = [
    ...musicSurfaces,
    'playback',
    'recordListen',
  ] as const;
  private readonly fixtures;
  private readonly history = new Map<
    string,
    Map<string, MusicListen & { listenedAt: string }>
  >();

  constructor(
    uidA: string,
    uidB: string,
    private readonly now = Date.now,
  ) {
    if (!uidA || !uidB || uidA === uidB)
      throw new Error('Invalid music preview accounts');
    this.fixtures = new Map([
      [
        uidA,
        [
          fixture('preview-a', 'Cuenta A', [
            'Brisa de Piura',
            'Cielo de Piura',
            'Ruta de Piura',
          ]),
          fixture(
            'preview-a2',
            'Canal alterno A',
            ['Marea de Paita', 'Puerto de Paita', 'Luz de Paita'],
            true,
          ),
        ],
      ],
      [
        uidB,
        [
          fixture('preview-b', 'Cuenta B', [
            'Río de Misiones',
            'Selva de Misiones',
            'Lluvia de Misiones',
          ]),
        ],
      ],
    ]);
  }

  accounts(uid: string) {
    return (this.fixtures.get(uid) ?? []).map(({ id, name }) => ({ id, name }));
  }

  private account(uid: string, accountId: string) {
    const account = this.fixtures.get(uid)?.find(({ id }) => id === accountId);
    if (!account) throw new LinkError(404, 'MUSIC_ACCOUNT_NOT_FOUND');
    return account;
  }

  async confirm(uid: string, accountId: string) {
    const { id, name, historyPaused } = this.account(uid, accountId);
    return { id, name, historyPaused };
  }

  async read(uid: string, accountId: string, page: MusicPageRequest) {
    const account = this.account(uid, accountId);
    const { songs, playlist } = account;
    let items: (MusicTrack | MusicPlaylist)[] = songs;
    let snapshot = 0;
    let excludedCount: number | undefined;
    switch (page.surface) {
      case 'home':
        items = [songs[2]!, playlist, songs[0]!];
        break;
      case 'playlists':
        items = [playlist];
        break;
      case 'playlist':
        if (page.playlistId !== playlist.id)
          throw new LinkError(404, 'MUSIC_PLAYLIST_NOT_FOUND');
        items = account.entries.filter(
          (item): item is MusicTrack =>
            item.kind === 'track' && 'playback' in item,
        );
        excludedCount = account.entries.length - items.length;
        break;
      case 'search': {
        const query = page.query!.toLocaleLowerCase('es');
        items = [...songs, playlist].filter((item) =>
          item.title.toLocaleLowerCase('es').includes(query),
        );
        break;
      }
      case 'history': {
        const listens = [...(this.history.get(accountId)?.entries() ?? [])];
        snapshot = page.continuation
          ? Number(page.continuation.split(':')[1])
          : listens.length;
        items = listens
          .slice(0, snapshot)
          .reverse()
          .map(([entryId, listen]) => ({
            ...songs.find((song) => song.id === listen.trackId)!,
            entryId,
            listenedAt: listen.listenedAt,
          }));
        break;
      }
    }
    const offset = page.continuation
      ? Number(page.continuation.split(':')[0])
      : 0;
    const end = offset + page.size;
    return {
      items: items.slice(offset, end),
      continuation: end < items.length ? end + ':' + snapshot : undefined,
      ...(page.surface === 'playlist' ? { playlist, excludedCount } : {}),
    };
  }

  async findListen(uid: string, accountId: string, id: string) {
    this.account(uid, accountId);
    const listen = this.history.get(accountId)?.get(id);
    return listen
      ? { trackId: listen.trackId, listenedMs: listen.listenedMs }
      : null;
  }

  async recordListen(
    uid: string,
    accountId: string,
    id: string,
    listen: MusicListen,
  ) {
    const account = this.account(uid, accountId);
    const track = account.songs.find(({ id }) => id === listen.trackId);
    if (!track) throw new LinkError(404, 'MUSIC_TRACK_NOT_FOUND');
    if (listen.listenedMs < track.durationSeconds * 500)
      throw new LinkError(400, 'MUSIC_LISTEN_TOO_SHORT');
    if (account.historyPaused) return;
    const history = this.history.get(accountId) ?? new Map();
    this.history.set(accountId, history);
    const existing = history.get(id);
    if (existing?.trackId === track.id) return;
    if (existing) throw new LinkError(409, 'MUSIC_LISTEN_CONFLICT');
    if (history.size >= 1000)
      throw new LinkError(409, 'MUSIC_PREVIEW_HISTORY_FULL');
    history.set(id, {
      ...listen,
      listenedAt: new Date(this.now()).toISOString(),
    });
  }
}

export function createPreviewMusicProvider(env = process.env) {
  if (env.YOUTUBE_MUSIC_PREVIEW_ENABLED !== 'true') return null;
  if (env.NODE_ENV === 'production')
    throw new Error('YouTube Music preview requires an isolated test backend');
  return new PreviewMusicProvider(
    env.YOUTUBE_MUSIC_PREVIEW_UID_A?.trim() ?? '',
    env.YOUTUBE_MUSIC_PREVIEW_UID_B?.trim() ?? '',
  );
}
