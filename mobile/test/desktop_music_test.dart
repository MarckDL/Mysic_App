import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/desktop_music_client.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/connected_library/presentation/desktop_music_access.dart';
import 'package:mysic/features/playback/application/track_playback_controller.dart';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

class _Store extends DesktopSessionStore {
  _Store(super.uid);
  String? saved;
  @override
  Future<String?> read() async => saved;
  @override
  Future<void> write(String? value) async => saved = value;
}

const _song = {
  'id': 'AbC01234567',
  'title': 'Again',
  'artist': 'Artista',
  'durationSeconds': 127,
};

class _DesktopService {
  bool linked = true,
      personal = true,
      expired = false,
      validCookie = true,
      wrongPassword = false,
      redirectAudio = false,
      legacy = false;
  final requests = <RequestOptions>[];
  final dio = Dio();
  _DesktopService() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request);
          final path = request.uri.path, query = request.queryParameters;
          expect(request.uri.origin, 'https://myslc.duckdns.org');
          expect(request.followRedirects, isFalse);
          expect(request.headers.containsKey('Authorization'), isFalse);
          void reply(Object data, {int status = 200, Headers? headers}) {
            if (data is ResponseBody && headers != null) {
              data.headers = headers.map;
            }
            handler.resolve(
              Response<dynamic>(
                requestOptions: request,
                data: data,
                statusCode: status,
                headers: headers,
              ),
            );
          }

          if (path == '/api/auth/login') {
            expect(request.headers['Cookie'], isNull);
            if (wrongPassword) {
              reply({}, status: 401);
              return;
            }
            reply(
              {
                'user': {'id': '0' * 24, 'username': 'Mi escritorio'},
              },
              headers: Headers.fromMap({
                'set-cookie': [
                  'mysic_session=test-session; Path=/; HttpOnly${validCookie ? '; Secure' : ''}',
                ],
              }),
            );
            return;
          }
          expect(
            (request.headers['cookie'] ?? request.headers['Cookie']),
            'mysic_session=test-session',
          );
          if (expired) {
            reply({}, status: 401);
            return;
          }
          switch (path) {
            case '/api/youtube/account':
              reply({'connected': linked, 'personalized': linked});
              return;
            case '/api/youtube/home':
              reply({
                'personalized': personal,
                'shelves': [
                  {
                    'items': [
                      {'kind': 'song', ..._song},
                      {
                        'kind': 'album',
                        'id': 'MPREb1',
                        'title': 'Álbum recomendado',
                      },
                    ],
                  },
                ],
                'continuation': 'mas',
              });
              return;
            case '/api/youtube/home/more':
              expect(query['token'], 'mas');
              reply({
                'shelves': [
                  {
                    'items': [
                      {'kind': 'artist', 'id': 'UC111', 'name': 'Artista'},
                    ],
                  },
                ],
              });
              return;
            case '/api/youtube/library/liked-songs':
              if (legacy) {
                reply({}, status: 404);
                return;
              }
              reply({
                'items': [if (query['cursor'] == null) _song],
                'continuation': query['cursor'] == null ? 'p2' : null,
              });
              return;
            case '/api/youtube/library':
              reply({
                'likedSongs': [_song],
              });
              return;
            case '/api/youtube/library/albums':
              reply({
                'items': [
                  {'id': 'MPREb1', 'title': 'Guardado'},
                ],
              });
              return;
            case '/api/youtube/library/playlists':
              reply({
                'items': [
                  {'id': 'VLPL123', 'title': 'Playlist musical'},
                ],
              });
              return;
            case '/api/youtube/library/subscriptions':
              reply({
                'items': [
                  {'id': 'UC111', 'name': 'Mi artista'},
                ],
              });
              return;
            case '/api/youtube/search':
              expect(query, {'q': 'again', 'type': 'song'});
              reply({
                'items': [_song],
              });
              return;
            case '/api/youtube/artist/UC111/songs':
              reply({
                'name': 'Mi artista',
                'songs': [_song],
              });
              return;
            case '/api/youtube/album/MPREb1':
              reply({
                'title': 'Guardado',
                'tracks': [_song],
              });
              return;
            case '/api/youtube/playlist/PL123':
              reply({
                'title': 'Playlist musical',
                'songs': [_song],
              });
              return;
            case '/api/youtube/stream/AbC01234567':
              if (redirectAudio) {
                reply(
                  ResponseBody.fromBytes([], 302),
                  status: 302,
                  headers: Headers.fromMap({
                    'location': ['https://example.test/other'],
                  }),
                );
                return;
              }
              final range = request.headers['Range'];
              if (range != null) expect(range, 'bytes=2-3');
              reply(
                ResponseBody.fromBytes(
                  range == null ? [1, 2, 3, 4] : [3, 4],
                  range == null ? 200 : 206,
                ),
                status: range == null ? 200 : 206,
                headers: Headers.fromMap({
                  'content-type': ['audio/mp4'],
                  'accept-ranges': ['bytes'],
                  'content-length': [range == null ? '4' : '2'],
                  if (range != null) 'content-range': ['bytes 2-3/4'],
                }),
              );
              return;
            default:
              throw StateError('Ruta inesperada $path');
          }
        },
      ),
    );
  }
}

void main() {
  late _Store store;
  late _DesktopService server;
  late DesktopMusicClient client;
  bool owns = true;
  setUp(() {
    store = _Store('uid-A');
    server = _DesktopService();
    owns = true;
    client = DesktopMusicClient(store, () => owns, dio: server.dio);
  });
  tearDown(() => client.close());
  Future<MusicConnection> login({bool remember = true}) =>
      client.login('test@example.invalid', 'solo-prueba', remember: remember);
  test(
    'expone Inicio y biblioteca únicamente tras verificar los datos personales del servidor',
    () async {
      final connection = await login(), g = connection.generation!;
      expect(connection.isDesktop, isTrue);
      expect(connection.personalization, 'verified');
      expect(connection.account!.name, 'Mi escritorio');
      expect(store.saved, isNot(contains('solo-prueba')));
      expect(store.saved, isNot(contains('test@example.invalid')));
      final home = await client.page(g, MusicSurface.home);
      expect(home.items.map((i) => i.title), ['Again', 'Álbum recomendado']);
      expect(
        server.requests.where((r) => r.uri.path.endsWith('/home')),
        hasLength(1),
      );
      expect(
        (await client.page(
          g,
          MusicSurface.home,
          cursor: home.nextCursor,
        )).items.single,
        isA<MusicArtist>(),
      );
      final liked = await client.page(g, MusicSurface.liked);
      expect(liked.items.single, isA<MusicTrack>());
      expect(liked.nextCursor, 'p2');
      expect(
        (await client.page(g, MusicSurface.liked, cursor: 'p2')).items,
        isEmpty,
      );
      final playlist = (await client.page(
        g,
        MusicSurface.playlists,
      )).items.single;
      expect(playlist.id, 'PL123');
      final album = (await client.page(g, MusicSurface.albums)).items.single;
      final artist = (await client.page(g, MusicSurface.artists)).items.single;
      for (final detail in [
        (MusicSurface.playlist, playlist.id),
        (MusicSurface.album, album.id),
        (MusicSurface.artist, artist.id),
      ]) {
        expect(
          (await client.page(
            g,
            detail.$1,
            playlistId: detail.$2,
          )).items.single.title,
          'Again',
        );
      }
      expect(
        (await client.page(
          g,
          MusicSurface.search,
          query: 'again',
        )).items.single.title,
        'Again',
      );
    },
  );
  test(
    'un despliegue con la biblioteca musical completa conserva sus Me gusta',
    () async {
      final connection = await login();
      server.legacy = true;
      final liked = await client.page(
        connection.generation!,
        MusicSurface.liked,
      );
      expect(liked.items.single.title, 'Again');
      expect(liked.nextCursor, isNull);
      expect(server.requests.last.uri.path, '/api/youtube/library');
    },
  );
  test(
    'rechaza credenciales incorrectas, un canal solo o un Inicio anónimo sin activar la biblioteca',
    () async {
      server.wrongPassword = true;
      await expectLater(
        login(),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'DESKTOP_LOGIN'),
        ),
      );
      server.wrongPassword = false;
      server.linked = false;
      await expectLater(
        login(),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'DESKTOP_MUSIC_LINK'),
        ),
      );
      server.linked = true;
      server.personal = false;
      await expectLater(
        login(),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'DESKTOP_HOME'),
        ),
      );
      server.personal = true;
      server.validCookie = false;
      await expectLater(login(), throwsA(isA<ApiFailure>()));
      expect(store.saved, isNull);
      expect(await client.connection(), isNull);
    },
  );
  test(
    'restaura una sesión por usuario y mantiene explícita su caducidad',
    () async {
      final g = (await login()).generation;
      final restarted = DesktopMusicClient(store, () => true, dio: server.dio);
      addTearDown(restarted.close);
      expect((await restarted.connection())!.generation, g);
      final other = DesktopMusicClient(_Store('uid-B'), () => true);
      addTearDown(other.close);
      expect(await other.connection(), isNull);
      server.expired = true;
      await expectLater(
        restarted.page(g!, MusicSurface.liked),
        throwsA(isA<ApiFailure>()),
      );
      expect((await restarted.connection())!.status, MusicLinkStatus.expired);
      await restarted.disconnect();
      expect(store.saved, isNull);
      expect(await restarted.connection(), isNull);
    },
  );
  test(
    'entrega audio al reproductor propio con rangos e invalida el acceso al cambiar de cuenta',
    () async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'A'));
      final api = AuthenticatedApiClient(auth, baseUrl: 'https://example.test');
      addTearDown(api.close);
      final engine = FakeTrackAudioEngine();
      final player = TrackPlaybackController(auth, engine, 'A');
      addTearDown(player.dispose);
      final model = MusicModeController(
        MusicModeClient(api, desktop: client),
        () => owns,
        player.clear,
      );
      addTearDown(model.dispose);
      await model.connectDesktop(
        'test@example.invalid',
        'solo-prueba',
        remember: false,
      );
      expect(store.saved, isNull);
      final g = model.connection!.generation!;
      final home = await model.page(g, MusicSurface.home);
      final track = model.playbackTrack(g, home.items.first as MusicTrack);
      expect(track.id, 'youtube:AbC01234567');
      await player.playQueue([track]);
      expect(player.phase, TrackAudioPhase.playing);
      expect(engine.lastReader, isNotNull);
      final range = await engine.lastReader!(2, 4);
      expect(range.total, 4);
      expect(range.offset, 2);
      expect(await range.stream.expand((v) => v).toList(), [3, 4]);
      server.redirectAudio = true;
      await expectLater(
        engine.lastReader!(null, null),
        throwsA(isA<PlaybackSourceFailure>()),
      );
      owns = false;
      final count = server.requests.length;
      await expectLater(
        engine.lastReader!(null, null),
        throwsA(isA<ApiFailure>()),
      );
      expect(server.requests, hasLength(count));
    },
  );
  testWidgets(
    'el formulario muestra el destino y conserva el vínculo después de un error de contraseña',
    (tester) async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'A'));
      final api = AuthenticatedApiClient(auth, baseUrl: 'https://example.test');
      addTearDown(api.close);
      final model = MusicModeController(
        MusicModeClient(api, desktop: client),
        () => true,
        () async {},
      );
      addTearDown(model.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DesktopMusicAccess(model))),
      );
      await tester.tap(find.text('Conectar Mysic de escritorio'));
      await tester.pumpAndSettle();
      expect(find.textContaining('myslc.duckdns.org'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isTrue,
      );
      await tester.enterText(
        find.byType(TextField).at(0),
        'test@example.invalid',
      );
      await tester.enterText(find.byType(TextField).at(1), 'solo-prueba');
      server.wrongPassword = true;
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('rechazó el correo'), findsOneWidget);
      expect(store.saved, isNull);
    },
  );
}
