import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/app/mysic_app.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/authentication/domain/mysic_profile.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/device_recordings.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_screen.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_host.dart';
import 'package:mysic/features/history/data/history_client.dart';
import 'package:mysic/features/history/application/listening_tracker.dart';
import 'package:mysic/features/playback/application/playback_providers.dart';
import 'package:mysic/features/playback/application/track_playback_controller.dart';
import 'package:mysic/features/playback/domain/playback_resolution.dart';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';

import 'package:mysic/features/connected_library/application/connected_controller.dart';
import 'package:mysic/features/connected_library/application/connected_host.dart';
import 'package:mysic/features/connected_library/data/connected_client.dart';

import 'support/fake_connected_library.dart' as oauth;
import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

const a = MusicAccount('a', 'Cuenta A', false);
const a2 = MusicAccount('a2', 'Canal alterno A', true);
const b = MusicAccount('b', 'Cuenta B', false);
const capabilities = {
  'home',
  'songs',
  'playlists',
  'playlist',
  'search',
  'history',
  'playback',
  'recordListen',
};

class _SessionFixture extends MusicModeClient {
  _SessionFixture(
    this.accounts,
    AuthenticatedApiClient api, {
    this.direct = false,
  }) : super(api);
  final bool direct;
  final List<MusicAccount> accounts;
  MusicAccount? account;
  int links = 0;
  int writes = 0;
  bool loseResponse = false;
  bool expired = false;
  int epoch = 4;
  int? recordedEpoch;
  Completer<MusicPage>? pending;
  Completer<MusicConnection>? pendingConnection;
  final recorded = <String, MusicTrack>{};

  @override
  Future<MusicConnection> connection() async {
    final pending = pendingConnection;
    if (pending != null) {
      pendingConnection = null;
      return pending.future;
    }
    return MusicConnection(
      status: account == null
          ? MusicLinkStatus.unlinked
          : expired
          ? MusicLinkStatus.expired
          : MusicLinkStatus.linked,
      provider: direct ? 'youtubeOAuth' : 'preview',
      accounts: direct ? [] : accounts,
      account: account,
      generation: account == null ? null : '${account!.id}-$links',
      libraryId: direct && account != null ? 'library-${account!.id}' : null,
      activityEpoch: epoch,
      capabilities: direct
          ? {
              'home',
              'albums',
              'album',
              'songs',
              'liked',
              'playlists',
              'playlist',
              'playback',
              'search',
              'recordInMysic',
              'mysicRecents',
              'onRepeat',
              'artists',
              'artist',
            }
          : capabilities,
    );
  }

  @override
  Future<MusicConnection> link(String id, String? generation) async {
    account = accounts.singleWhere((entry) => entry.id == id);
    links++;
    expired = false;
    return connection();
  }

  @override
  Future<void> unlink(String generation) async => account = null;

  @override
  Future<MusicPage> page(
    String generation,
    MusicSurface surface, {
    String? playlistId,
    String? query,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    if (pending case final pending?) return pending.future;
    final current = account!;
    final playlist = MusicPlaylist(
      current.id,
      'Lista de ${current.name}',
      true,
    );
    final one = MusicTrack(
      direct ? '9xgftPjTz7c' : '${current.id}-1',
      'Canción de ${current.name}',
      'Mysic',
      8,
      !direct,
      null,
      audioUri: direct
          ? Uri.https('media.example.test', '/recording.mp3')
          : null,
    );
    final two = MusicTrack(
      direct ? 'k1HtSmS4Tc4' : '${current.id}-2',
      'Siguiente de ${current.name}',
      'Mysic',
      8,
      !direct,
      null,
    );
    return switch (surface) {
      MusicSurface.home => MusicPage(
        [
          if (direct)
            MusicTrack(
              'aaaaaaaaaaa',
              'Recomendado para ${current.name}',
              'Artista',
              150,
              false,
              null,
              nativePlayback: true,
            )
          else
            one,
          playlist,
        ],
        null,
        null,
        0,
      ),
      MusicSurface.playlists => MusicPage([playlist], null, null, 0),
      MusicSurface.playlist =>
        playlistId == current.id
            ? MusicPage([one, two], null, playlist, 2)
            : throw const ApiFailure(
                'No disponible.',
                code: 'MUSIC_PLAYLIST_NOT_FOUND',
              ),
      MusicSurface.songs ||
      MusicSurface.liked => MusicPage([one, two], null, null, 0),
      MusicSurface.search => MusicPage(
        [one, playlist].where((item) => item.title.contains(query!)).toList(),
        null,
        null,
        0,
      ),
      MusicSurface.albums => const MusicPage(
        [MusicAlbum('MPREb1', 'Disco guardado')],
        null,
        null,
        0,
      ),
      MusicSurface.album => MusicPage([one], null, null, 0, 'Disco guardado'),

      MusicSurface.artists ||
      MusicSurface.onRepeat ||
      MusicSurface.artist ||
      MusicSurface.mysicRecents => const MusicPage([], null, null, 0),
      MusicSurface.history => MusicPage(
        recorded.values.toList(),
        null,
        null,
        0,
      ),
    };
  }

  @override
  Future<bool> hasListen(String generation, String id) async =>
      recorded.containsKey(id);

  @override
  Future<void> activityPreference(String generation, {bool? paused}) async {
    final current = account!;
    if (paused == null) {
      recorded.clear();
    } else {
      account = MusicAccount(current.id, current.name, paused);
    }
    epoch++;
  }

  @override
  Future<void> record(
    String generation,
    String id,
    String trackId,
    int listenedMs, {
    int? activityEpoch,
  }) async {
    writes++;
    recordedEpoch = activityEpoch;
    recorded[id] = MusicTrack(
      trackId,
      'Escucha de ${account!.name}',
      'Mysic',
      8,
      true,
      DateTime.utc(2026, 11, 19),
    );
    if (loseResponse) throw const ApiFailure('Sin respuesta.');
  }
}

class _DeviceFixture extends DeviceRecordings {
  _DeviceFixture() : super('A');
  final files = <String, Uri>{};
  String? scope;
  @override
  Future<Map<String, Uri>> open(
    String? generation,
    bool Function() stillCurrent,
  ) async {
    if (scope != generation) files.clear();
    scope = generation;
    return Map.of(files);
  }

  @override
  Future<Uri?> attach(
    String generation,
    String id,
    bool Function() stillCurrent,
  ) async => stillCurrent() ? files[id] = Uri.file('/privado/$id.media') : null;
}

class _ConsentClient extends oauth.Client {
  _ConsentClient(this.music);
  final _SessionFixture music;
  @override
  Future<void> confirm(String id, Json body, CancelToken cancel) async {
    await super.confirm(id, body, cancel);
    await music.link(a.id, null);
  }

  @override
  Future<void> unlink(CancelToken cancel, {String? generation}) async {
    await super.unlink(cancel, generation: generation);
    await music.unlink('fixture-generation');
  }
}

void main() {
  test('la biblioteca conserva las portadas de playlists y canales', () {
    const cover = 'https://i.ytimg.com/vi/ABCDEFGHIJK/default.jpg';
    final page = MusicPage.fromJson({
      'items': [
        {
          'id': 'PL1',
          'kind': 'playlist',
          'title': 'Lista',
          'private': true,
          'thumbnailUrl': cover,
        },
        {
          'id': 'UC1',
          'kind': 'artist',
          'title': 'Grupo',
          'thumbnailUrl': cover,
        },
      ],
    });
    expect((page.items.first as MusicPlaylist).thumbnailUrl, cover);
    expect((page.items.last as MusicArtist).thumbnailUrl, cover);
  });
  test(
    'renovar el canal conserva la fuente del teléfono y rechaza acciones de la sesión anterior',
    () async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'A'));
      final api = AuthenticatedApiClient(auth, baseUrl: 'https://example.test');
      addTearDown(api.close);
      final client = _SessionFixture([a, a2], api, direct: true)..account = a;
      final device = _DeviceFixture();
      final music = MusicModeController(
        client,
        () => true,
        () async {},
        device: device,
      );
      addTearDown(music.dispose);
      await music.refresh();
      final first = music.connection!.generation!;
      expect(await music.attachAudio(first, 'ABCDEFGHIJK'), isTrue);
      final file = music.deviceAudio('ABCDEFGHIJK');
      await client.link(a.id, first);
      await music.refresh();
      expect(music.isCurrent(first), isFalse);
      expect(music.deviceAudio('ABCDEFGHIJK'), file);
      expect(await music.attachAudio(first, 'ABCDEFGHIJK'), isFalse);
      await client.link(a2.id, music.connection!.generation);
      await music.refresh();
      expect(music.deviceAudio('ABCDEFGHIJK'), isNull);
      expect(device.files, isEmpty);
    },
  );
  test(
    'identifica el servidor anterior sin recurrir al catálogo general',
    () async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'A'));
      int status = 404;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) => handler.reject(
              DioException.badResponse(
                statusCode: status,
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: status,
                  data: {
                    'error': {
                      'code': status == 404 ? 'NOT_FOUND' : 'INTERNAL_ERROR',
                    },
                  },
                ),
              ),
            ),
          ),
        );
      final api = AuthenticatedApiClient(
        auth,
        baseUrl: 'https://example.test',
        dio: dio,
      );
      addTearDown(api.close);
      final client = MusicModeClient(api);
      final missing = await client.connection();
      expect(missing.status, MusicLinkStatus.unavailable);
      expect(missing.serverPending, isTrue);
      status = 503;
      await expectLater(client.connection(), throwsA(isA<ApiFailure>()));
      expect(auth.signOutCount, 0);
    },
  );

  testWidgets(
    'el servidor antiguo nunca muestra playlists o favoritos normales como datos de Music',
    (tester) async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'A'));
      final api = AuthenticatedApiClient(auth, baseUrl: 'https://example.test');
      addTearDown(api.close);
      final fixture = _SessionFixture([a], api)
        ..pendingConnection = (Completer<MusicConnection>()
          ..complete(
            const MusicConnection(
              status: MusicLinkStatus.unavailable,
              provider: 'serverPending',
            ),
          ));
      final controller = MusicModeController(fixture, () => true, () async {});
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MusicModeHost(
            controller: controller,
            child: const MusicModeSurface(
              surface: MusicSurface.home,
              local: Text('Biblioteca propia'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('aún no ofrece'), findsOneWidget);
      expect(find.text('Biblioteca propia'), findsNothing);
      await tester.tap(find.text('Usar mi biblioteca de Mysic'));
      await tester.pumpAndSettle();
      expect(find.text('Biblioteca propia'), findsOneWidget);
    },
  );
  test(
    'un cambio de vínculo durante una consulta oculta la generación anterior inmediatamente',
    () async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'A'));
      final api = AuthenticatedApiClient(auth, baseUrl: 'https://example.test');
      addTearDown(api.close);
      final client = _SessionFixture([a, b], api, direct: true);
      final old = await client.link(a.id, null);
      final music = MusicModeController(client, () => true, () async {});
      addTearDown(music.dispose);
      await music.refresh();
      expect(music.isCurrent(old.generation!), isTrue);
      final gate = Completer<MusicConnection>();
      client.pendingConnection = gate;
      final started = music.refresh();
      await client.link(b.id, old.generation);
      await music.refresh(invalidate: true);
      expect(music.isCurrent(old.generation!), isFalse);
      expect(music.connection, isNull);
      gate.complete(old);
      await started;
      await Future<void>.delayed(Duration.zero);
      expect(music.connection?.account?.id, b.id);
      expect(music.isCurrent(old.generation!), isFalse);
    },
  );

  testWidgets(
    'regresa del consentimiento a Biblioteca y reproduce una fuente autorizada en Mysic',
    (tester) async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'A'));
      final api = AuthenticatedApiClient(auth, baseUrl: 'https://example.test');
      addTearDown(api.close);
      final music = _SessionFixture([a], api, direct: true);
      final files = _DeviceFixture();
      late TrackPlaybackController player;
      final consent = _ConsentClient(music);
      final platform = oauth.MemoryPlatform();
      var engine = FakeTrackAudioEngine();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            verifiedSessionProvider.overrideWith(
              (ref) async => const MysicProfile(
                id: 'test-A',
                firebaseUid: 'A',
                displayName: 'A',
              ),
            ),
            recentListeningProvider.overrideWith((ref, uid) => []),
            youtubeMusicModeEnabledProvider.overrideWithValue(true),
            youtubePilotProvider.overrideWithValue(true),
            connectedControllerProvider.overrideWith((ref, uid) {
              final controller = ConnectedController(uid, consent, platform);
              ref.onDispose(controller.dispose);
              return controller;
            }),
            trackAudioEngineFactoryProvider.overrideWithValue(
              () => engine = FakeTrackAudioEngine(),
            ),
            musicModeControllerProvider.overrideWith((ref, uid) {
              player = ref.watch(trackPlaybackControllerProvider);
              final controller = MusicModeController(
                music,
                () => true,
                player.clear,
                device: files,
                onDeviceAudioRemoved: player.removeDeviceAudio,
              );
              ref.onDispose(controller.dispose);
              return controller;
            }),
          ],
          child: const MysicApp(firebaseReady: true),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Abrir cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vincular YouTube Music'));
      await tester.pumpAndSettle();
      expect(platform.uris.single.host, oauth.host);
      expect(find.text('Esperando autorización'), findsOneWidget);
      platform.incoming = (id: oauth.id, ref: null);
      platform.notifyReturn!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar este canal'));
      await tester.pumpAndSettle();
      expect(consent.confirms, [
        {'channelId': 'ch'},
      ]);
      expect(find.text('Lista de Cuenta A'), findsOneWidget);
      await tester.tap(find.text('Álbumes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disco guardado'));
      await tester.pumpAndSettle();
      expect(find.text('Canción de Cuenta A'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inicio').last);
      await tester.pumpAndSettle();
      expect(find.text('Recomendaciones de YouTube Music'), findsOneWidget);
      await tester.tap(find.text('Recomendado para Cuenta A'));
      await tester.pumpAndSettle();
      expect(engine.sourceId, 'aaaaaaaaaaa');
      expect(engine.lastLicensedAudio, isNull);
      expect(engine.lastDeviceAudio, isNull);
      expect(player.current!.isConnectedAudio, isTrue);
      expect(platform.uris, hasLength(1));
      await tester.tap(find.byTooltip('Ver mis Me gusta de YouTube Music'));
      await tester.pumpAndSettle();
      expect(find.text('Canción de Cuenta A'), findsOneWidget);
      expect(find.text('Recomendado para Cuenta A'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Biblioteca').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Me gusta de YouTube Music'));
      await tester.pumpAndSettle();
      expect(find.text('Canción de Cuenta A'), findsOneWidget);
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lista de Cuenta A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Canción de Cuenta A'));
      await tester.pumpAndSettle();
      expect(engine.sourceId, '9xgftPjTz7c');
      expect(
        engine.lastLicensedAudio,
        Uri.https('media.example.test', '/recording.mp3'),
      );
      expect(engine.prefetched, isEmpty);
      expect(music.writes, 0);
      expect(find.text('Canción de Cuenta A'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final initialPlays = engine.plays;
      final options = find.byTooltip('Opciones de Siguiente de Cuenta A');
      await tester.ensureVisible(options);
      await tester.tap(options);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vincular archivo de audio'));
      await tester.pumpAndSettle();
      expect(find.textContaining('En este dispositivo'), findsOneWidget);
      await tester.tap(options);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reproducir a continuación'));
      await tester.pumpAndSettle();
      expect(engine.plays, initialPlays);
      expect(player.queue, hasLength(2));
      await player.next();
      await tester.pump();
      expect(engine.lastDeviceAudio, files.files['k1HtSmS4Tc4']);
      expect(engine.lastLicensedAudio, isNull);
      expect(engine.prefetched, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Abrir cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gestionar cuenta vinculada'));
      await tester.pumpAndSettle();
      expect(find.text('Cuenta de YouTube Music'), findsOneWidget);
      expect(find.byTooltip('Abrir YouTube Music'), findsNothing);
      await tester.tap(find.byTooltip('Opciones del vínculo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desvincular YouTube'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desvincular'));
      await tester.pumpAndSettle();
      expect(consent.unlinks, 1);
      expect(music.account, isNull);
      expect(find.text('Canción de Cuenta A'), findsNothing);
      expect(auth.signOutCount, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('efecto del modo en las pestañas, cola y cambio de dos cuentas', (
    tester,
  ) async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'A'));
    final api = AuthenticatedApiClient(auth, baseUrl: 'https://example.test');
    addTearDown(api.close);
    final fixtures = {
      'A': _SessionFixture([a, a2], api),
      'B': _SessionFixture([b], api)..account = b,
    };
    var engine = FakeTrackAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          verifiedSessionProvider.overrideWith((ref) async {
            final uid = ref.watch(authStateProvider).requireValue!.uid;
            return MysicProfile(
              id: 'test-$uid',
              firebaseUid: uid,
              displayName: uid,
            );
          }),
          recentListeningProvider.overrideWith((ref, uid) => []),
          youtubeMusicModeEnabledProvider.overrideWithValue(true),
          trackAudioEngineFactoryProvider.overrideWithValue(
            () => engine = FakeTrackAudioEngine(),
          ),
          musicModeControllerProvider.overrideWith((ref, uid) {
            final playback = ref.watch(trackPlaybackControllerProvider);
            final controller = MusicModeController(
              fixtures[uid]!,
              () => auth.currentUser?.uid == uid,
              playback.clear,
            );
            ref.onDispose(controller.dispose);
            return controller;
          }),
        ],
        child: const MysicApp(firebaseReady: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido, A'), findsOneWidget);
    await tester.tap(find.byTooltip('Abrir cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activar YouTube Music'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuenta A'));
    await tester.pumpAndSettle();
    expect(find.text('Modo activo · Cuenta A'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Canción de Cuenta A'), findsOneWidget);
    expect(find.text('Bienvenido, A'), findsNothing);

    await tester.tap(find.text('Buscar').hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cuenta A');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Canción de Cuenta A'), findsOneWidget);
    await tester.tap(find.text('Biblioteca').hitTestable().last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lista de Cuenta A'));
    await tester.pumpAndSettle();
    expect(find.text('Elementos omitidos: 2'), findsOneWidget);
    await tester.tap(find.text('Siguiente de Cuenta A'));
    await tester.pumpAndSettle();
    expect(find.text('Siguiente de Cuenta A').hitTestable(), findsOneWidget);
    expect(engine.sourceId, PlaybackResolution.demoId);
    expect(engine.prefetched, isEmpty);
    final aEngine = engine;
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abrir cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambiar cuenta o canal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canal alterno A'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('Cuenta A', skipOffstage: false), findsNothing);
    expect(aEngine.stops, greaterThan(1));
    await tester.tap(find.text('Inicio').hitTestable().last);
    await tester.pumpAndSettle();
    expect(find.text('Canción de Canal alterno A'), findsOneWidget);
    await tester.tap(find.text('Canción de Canal alterno A'));
    await tester.pumpAndSettle();

    auth.changeUser(const AuthUser(uid: 'B'));
    await tester.pumpAndSettle();
    expect(find.text('Canción de Cuenta B'), findsOneWidget);
    expect(find.textContaining('Cuenta A', skipOffstage: false), findsNothing);
    expect(aEngine.stops, greaterThan(2));
    expect(
      find.textContaining('Canal alterno A', skipOffstage: false),
      findsNothing,
    );
    await tester.tap(find.text('Canción de Cuenta B'));
    await tester.pumpAndSettle();
    expect(engine.sourceId, PlaybackResolution.demoId);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abrir Recientes'));
    await tester.pumpAndSettle();
    expect(find.text('Aún no hay escuchas.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abrir cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desvincular y volver a Mysic'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Bienvenido, B'), findsOneWidget);
    expect(find.textContaining('Cuenta B'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'descarta respuesta tardía y reconcilia una escucha tras perder la confirmación',
    (tester) async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'A'));
      final api = AuthenticatedApiClient(auth, baseUrl: 'https://example.test');
      final fixture = _SessionFixture([a, a2], api)..account = a;
      final controller = MusicModeController(fixture, () => true, () async {});
      addTearDown(controller.dispose);
      addTearDown(api.close);
      await controller.refresh();
      final original = controller.connection!.generation!;
      fixture.loseResponse = true;
      controller.onListened(original, 'listen-1', 'a-1', 4200);
      await tester.pump();
      expect(fixture.recorded, hasLength(1));
      await tester.pump(const Duration(seconds: 15));
      expect(fixture.writes, 1);

      final blocked = fixture.pending = Completer<MusicPage>();
      final request = expectLater(
        controller.page(original, MusicSurface.home),
        throwsA(isA<ApiFailure>()),
      );
      await controller.select(a2);
      blocked.complete(const MusicPage([], null, null, 0));
      await request;
      expect(controller.connection!.account!.id, a2.id);
      controller.onListened(
        controller.connection!.generation!,
        'listen-2',
        'a2-1',
        4200,
      );
      await tester.pump();
      expect(fixture.writes, 1);

      fixture.expired = true;
      await controller.refresh();
      expect(controller.connection!.status, MusicLinkStatus.expired);
      expect(controller.showMusic, isTrue);
      await controller.select(a2);
      expect(controller.connection!.status, MusicLinkStatus.linked);
    },
  );

  testWidgets(
    'el audio de dispositivo registra tiempo audible en el vínculo y respeta pausa y borrado',
    (tester) async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'A'));
      final api = AuthenticatedApiClient(auth, baseUrl: 'https://example.test');
      final client = _SessionFixture([a], api, direct: true)..account = a;
      final engine = FakeTrackAudioEngine();
      final clock = _ManualStopwatch();
      final player = TrackPlaybackController(
        auth,
        engine,
        'A',
        history: ListeningTracker(api, () => true, 'A', clock: clock),
      );
      final music = MusicModeController(client, () => true, player.clear);
      addTearDown(music.dispose);
      addTearDown(player.dispose);
      await music.refresh();
      final generation = music.connection!.generation!;
      final track = const MusicTrack(
        '9xgftPjTz7c',
        'Tema',
        'Canal',
        8,
        false,
        null,
      ).toPlaybackTrack(deviceAudio: Uri.file('/privado/tema.media'));
      Future<void> play() => player.playQueue([
        track,
      ], listenForTrack: () => music.listenForTrack(generation));
      await play();
      clock.advance(3500);
      await player.pause();
      clock.advance(10000);
      expect(client.recorded, isEmpty);
      await player.resume();
      clock.advance(500);
      engine.events.add(TrackAudioPhase.completed);
      await tester.pump();
      expect(client.writes, 1);
      expect(client.recorded.values.single.id, '9xgftPjTz7c');
      expect(client.recordedEpoch, client.epoch);
      await music.updateActivity(generation, paused: true);
      await play();
      clock.advance(5000);
      engine.events.add(TrackAudioPhase.completed);
      await tester.pump();
      expect(client.writes, 1);
      await music.updateActivity(generation);
      expect(client.recorded, isEmpty);
      await music.updateActivity(generation, paused: false);
      await play();
      clock.advance(3500);
      await music.updateActivity(generation);
      clock.advance(500);
      engine.events.add(TrackAudioPhase.completed);
      await tester.pump();
      expect(client.recorded, isEmpty);
      await play();
      clock.advance(5000);
      engine.events.add(TrackAudioPhase.completed);
      await tester.pump();
      expect(client.writes, 2);
      expect(client.recordedEpoch, client.epoch);
      await player.clear();
      player.dispose();
      await tester.pump();
    },
  );

  testWidgets('solo el audio en marcha activa el registro del preview', (
    tester,
  ) async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'A'));
    final engine = FakeTrackAudioEngine();
    final api = AuthenticatedApiClient(auth, baseUrl: 'https://example.test');
    final clock = _ManualStopwatch();
    final playback = TrackPlaybackController(
      auth,
      engine,
      'A',
      history: ListeningTracker(api, () => true, 'A', clock: clock),
    );
    final recorded = <String>[];
    final preview = const MusicTrack(
      'a-1',
      'Canción',
      'Mysic',
      8,
      true,
      null,
    ).toPlaybackTrack();
    await playback.playQueue([
      preview,
    ], onPreviewListened: (_, id, _) => recorded.add(id));
    clock.advance(3999);
    await playback.pause();
    clock.advance(5000);
    expect(recorded, isEmpty);
    await playback.resume();
    clock.advance(1);
    engine.events.add(TrackAudioPhase.completed);
    await tester.pump();
    expect(recorded, ['a-1']);
    await playback.clear();
    expect(recorded, ['a-1']);
    playback.dispose();
    await tester.pump();
  });
}

class _ManualStopwatch implements Stopwatch {
  bool _running = false;
  int _ms = 0;

  void advance(int ms) {
    if (_running) _ms += ms;
  }

  @override
  int get elapsedMilliseconds => _ms;
  @override
  void start() => _running = true;
  @override
  void stop() => _running = false;
  @override
  void reset() => _ms = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
