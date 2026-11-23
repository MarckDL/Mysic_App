import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/history/data/local_listens.dart';
import 'package:mysic/features/ytm/data/ytm_client.dart';
import 'package:mysic/features/ytm/data/ytm_session.dart';

class _Store implements ListenStore {
  int recents = 0, tops = 0;

  MusicTrack track(String id, {int? plays}) => MusicTrack(
    id,
    'Tema $id',
    'Artista',
    200,
    false,
    DateTime(2026),
    nativePlayback: true,
    playCount: plays,
  );

  @override
  Future<List<MusicTrack>> recent({int limit = 100}) async {
    recents++;
    return [track('aaaaaaaaaaa')];
  }

  @override
  Future<List<MusicTrack>> mostPlayed({
    int days = 30,
    int minPlays = 2,
    int limit = 50,
  }) async {
    tops++;
    return [track('bbbbbbbbbbb', plays: 7)];
  }

  @override
  Future<void> record(LocalListen listen) async {}

  @override
  Future<void> clear() async {}

  @override
  set paused(bool value) {}

  @override
  Future<void> adoptLegacy() async {}

  @override
  Future<bool> importPending() async => false;

  @override
  Future<void> importAll(List<LocalListen> listens) async {}
}

MusicModeClient client(List<String> paths, {ListenStore? listens}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        paths.add(options.path);
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: {}),
        );
      },
    ),
  );
  return MusicModeClient(
    ytm: YtmClient(const YtmSession('SAPISID=t'), dio: dio),
    ytmAccount: () => const YtmAccount(name: 'Cuenta'),
    listens: listens,
  );
}

void main() {
  test('la cuenta ofrece Recientes y Lo más oído siempre', () async {
    final connection = await client([], listens: _Store()).connection();
    expect(
      connection.capabilities,
      containsAll(['mysicRecents', 'onRepeat', 'playlists', 'home']),
    );
  });

  test(
    'esas pantallas salen del teléfono y no hacen ninguna petición',
    () async {
      final paths = <String>[];
      final store = _Store();
      final mine = client(paths, listens: store);
      final recent = await mine.page('ytm', MusicSurface.mysicRecents);
      final history = await mine.page('ytm', MusicSurface.history);
      final top = await mine.page('ytm', MusicSurface.onRepeat);
      expect(recent.items.single.id, 'aaaaaaaaaaa');
      expect(history.items.single.id, 'aaaaaaaaaaa');
      expect((top.items.single as MusicTrack).playCount, 7);
      expect(store.recents, 2);
      expect(store.tops, 1);
      expect(paths, isEmpty);
    },
  );

  test('las demás pantallas se piden a YouTube Music', () async {
    final paths = <String>[];
    final mine = client(paths, listens: _Store());
    await mine
        .page('ytm', MusicSurface.playlists)
        .catchError((_) => MusicPage(const [], null, null, 0));
    expect(paths.single, contains('browse'));
  });
}
