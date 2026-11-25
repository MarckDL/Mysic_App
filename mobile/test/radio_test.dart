import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/playback/application/playback_providers.dart';
import 'package:mysic/features/playback/application/track_playback_controller.dart';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';
import 'package:mysic/features/radio/data/radio_store.dart';
import 'package:mysic/features/radio/domain/hls_track_info.dart';
import 'package:mysic/features/radio/domain/live_now_playing.dart';
import 'package:mysic/features/radio/domain/radio_mood.dart';
import 'package:mysic/features/radio/domain/radio_station.dart';
import 'package:mysic/features/radio/presentation/radio_shelf.dart';
import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

void main() {
  group('RadioStation', () {
    test('Shonan Beach FM: 78.9 FM, https y colores propios', () {
      const s = RadioStation.shonanBeachFm;
      expect(s.label, '78.9 FM');
      expect(s.streamUri, isNotNull);
      expect(s.colors, hasLength(2));
    });

    test('solo valen flujos https sin usuario ni fragmento', () {
      expect(RadioStation.validStream('http://a.test/x'), isNull);
      expect(RadioStation.validStream('https://u:p@a.test/x'), isNull);
      expect(RadioStation.validStream('https://a.test/x#f'), isNull);
      expect(RadioStation.validStream('https://a.test/x?k=1'), isNotNull);
    });

    test('toJson/fromJson ida y vuelta; los datos malos se descartan', () {
      final back = RadioStation.fromJson(RadioStation.shonanBeachFm.toJson());
      expect(back?.id, 'shonan-beach-fm');
      expect(back?.frequency, '78.9');
      expect(
        RadioStation.fromJson({'id': 'x', 'name': '', 'stream': 'z'}),
        isNull,
      );
      expect(RadioStation.fromJson('no'), isNull);
    });

    test('sin dial la etiqueta es EN VIVO', () {
      const s = RadioStation(id: 'a', name: 'A', stream: 'https://a.test/s');
      expect(s.label, 'EN VIVO');
    });

    test('toTrack es una pista en directo sin duración', () {
      final t = RadioStation.shonanBeachFm.toTrack();
      expect(t.isLive, isTrue);
      expect(t.isConnectedAudio, isTrue);
      expect(t.durationSeconds, isNull);
      expect(t.liveStream, RadioStation.shonanBeachFm.streamUri);
    });
  });

  group('RadioStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('radio_store'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('sin archivo salen las de fábrica', () async {
      final store = RadioStore.forTest(dir);
      await store.load();
      expect(store.stations.map((s) => s.id), [
        'shonan-beach-fm',
        'kdvs',
        'rovr',
      ]);
    });

    test('añadir y quitar se guardan y se leen de nuevo', () async {
      final store = RadioStore.forTest(dir);
      const extra = RadioStation(
        id: 'otra',
        name: 'Otra',
        stream: 'https://a.test/s',
      );
      await store.add(extra);
      await store.add(extra);
      expect(store.stations, hasLength(4));
      await store.remove('shonan-beach-fm');
      await store.remove('kdvs');
      await store.remove('rovr');
      final again = RadioStore.forTest(dir);
      await again.load();
      expect(again.stations.map((s) => s.id), ['otra']);
    });

    test('un archivo ilegible deja las de fábrica', () async {
      File(
        '${dir.path}${Platform.pathSeparator}radio_stations.json',
      ).writeAsStringSync('{no es json');
      final store = RadioStore.forTest(dir);
      await store.load();
      expect(store.stations, hasLength(3));
    });
  });

  group('lo que suena en la radio', () {
    (String?, String)? parse(String? raw) =>
        TrackPlaybackController.parseLiveTitle(raw, station: 'Shonan Beach FM');

    test('separa «Artista - Título»', () {
      expect(parse('Daft Punk - Digital Love'), ('Daft Punk', 'Digital Love'));
      expect(parse('  Sade  -  Smooth Operator '), ('Sade', 'Smooth Operator'));
    });

    test('sin separador, todo es el título', () {
      expect(parse('Smooth Operator'), (null, 'Smooth Operator'));
    });

    test('ignora vacío, la propia emisora y los avisos', () {
      expect(parse(null), isNull);
      expect(parse('   '), isNull);
      expect(parse('Shonan Beach FM'), isNull);
      expect(parse('Shonan Beach FM - offline'), isNull);
    });

    test('quita el prefijo de la emisora', () {
      expect(parse('Shonan Beach FM - Los Ultimos'), (null, 'Los Ultimos'));
    });

    test('el controlador lo muestra y lo borra al cambiar de pista', () async {
      final engine = FakeTrackAudioEngine();
      final controller = TrackPlaybackController(
        FakeAuthRepository(user: const AuthUser(uid: 'a')),
        engine,
        'a',
      );
      addTearDown(controller.dispose);
      await controller.playQueue([RadioStation.shonanBeachFm.toTrack()]);
      engine.liveTitleEvents.add('Sade - Smooth Operator');
      expect(controller.liveArtist, 'Sade');
      expect(controller.liveTitle, 'Smooth Operator');
      engine.liveTitleEvents.add('Shonan Beach FM - offline');
      expect(controller.liveTitle, isNull);
      engine.liveTitleEvents.add('Sade - Smooth Operator');
      await controller.playQueue([RadioStation.shonanBeachFm.toTrack()]);
      expect(controller.liveTitle, isNull);
    });
  });

  group('JSON de la emisora', () {
    test('lee programa, título, artista (aartist) y carátula', () {
      final info = LiveNowPlaying.parse({
        'program': 'MEMORY LANE AGAIN',
        'title': 'Beyond The Sea (La Mer)',
        'aartist': 'Johnny Desmond',
        'imagepath': 'https://www.beachfm.co.jp/a/b.jpg',
      });
      expect(info?.program, 'MEMORY LANE AGAIN');
      expect(info?.title, 'Beyond The Sea (La Mer)');
      expect(info?.artist, 'Johnny Desmond');
      expect(info?.artwork, 'https://www.beachfm.co.jp/a/b.jpg');
    });

    test('descarta carátulas no https y JSON sin título', () {
      expect(
        LiveNowPlaying.parse({
          'title': 'X',
          'imagepath': 'http://a.test/x.jpg',
        })?.artwork,
        isNull,
      );
      expect(LiveNowPlaying.parse({'title': '  '}), isNull);
      expect(LiveNowPlaying.parse([1]), isNull);
    });

    test('Spinitron: canción con su programa', () {
      final info = LiveNowPlaying.parse({
        'nowPlaying': {
          'title': "The Earworm's Garden",
          'djs': [
            {'name': 'muse'},
          ],
          'song': {
            'title': 'Heart Bleeding Out',
            'artist': 'Anthony Boccaleoni',
          },
        },
        'nextShow': {'title': 'Spreading Misinformation'},
      });
      expect(info?.title, 'Heart Bleeding Out');
      expect(info?.artist, 'Anthony Boccaleoni');
      expect(info?.program, "The Earworm's Garden");
      expect(info?.artwork, isNull);
    });

    test('Spinitron: sin canción, el programa y sus locutores', () {
      final info = LiveNowPlaying.parse({
        'nowPlaying': {
          'title': 'Spreading Misinformation',
          'djs': [
            {'name': 'ana'},
            {'name': 'luis'},
          ],
        },
      });
      expect(info?.title, 'Spreading Misinformation');
      expect(info?.artist, 'ana, luis');
      expect(info?.program, isNull);
      expect(LiveNowPlaying.parse({'nowPlaying': <String, Object?>{}}), isNull);
    });

    test('ROVR: HLS por https, sin dial, con logo y su programación', () {
      const s = RadioStation.rovr;
      expect(s.label, 'EN VIVO');
      expect(s.streamUri?.path, endsWith('.m3u8'));
      expect(s.toTrack().liveInfo?.queryParameters['date'], 'now');
      expect(RadioStation.fromJson(s.toJson())?.logo, s.logo);
    });

    Map<String, Object?> rovrJson({int? track}) => {
      'data': [
        {
          'startTime': '2026-11-25 18:00:00',
          'endTime': '2026-11-25 20:00:00',
          'show': {
            'title': 'Saturation Point',
            'curators': [
              {'name': 'soFa elsewhere'},
            ],
          },
          'playlist': {
            'playlistTags': [
              {'label': 'Brain'},
              {'label': 'DREAM'},
              {'label': 'chill'},
            ],
            'tracks': [
              {
                'title': 'Uno',
                'artist': 'Artista Uno',
                'label': 'Sello Uno',
                'albumCoverUrl': 'https://a.test/1.jpg',
              },
              {
                'title': 'Dos',
                'artist': 'Artista Dos',
                'albumCoverUrl': 'http://a.test/2.jpg',
              },
            ],
            'stitchedTracksMetadata': {
              'tracks_cues': [
                {'start': 16.4, 'end': 138.9, 'track_index': 0},
                {'start': 130.6, 'end': 271.2, 'track_index': 1},
              ],
            },
          },
        },
      ],
    };

    test('ROVR: la pista que suena según la hora dentro del programa', () {
      // La programación viene en hora de pared (la del huso de la señal) y se
      // compara con la del teléfono: aquí, un reloj de pared sin zona.
      // 18:01:00 = 60 s dentro del programa: primera pista.
      final at = DateTime(2026, 11, 25, 18, 1, 0);
      final first = LiveNowPlaying.parse(rovrJson(), now: at);
      expect(first?.title, 'Uno');
      expect(first?.artist, 'Artista Uno');
      expect(first?.program, 'Saturation Point');
      expect(first?.artwork, 'https://a.test/1.jpg');
      expect(first?.label, 'Sello Uno');
      expect(first?.curator, 'soFa elsewhere');
      // Los moods del programa, en mayúsculas y en su orden.
      expect(first?.moods, ['BRAIN', 'DREAM', 'CHILL']);
      // La línea de tiempo es la del programa (2 h), en la hora del teléfono.
      expect(first?.startedAt, DateTime(2026, 11, 25, 18, 0, 0));
      expect(first?.endsAt, DateTime(2026, 11, 25, 20, 0, 0));
      // La canción cambia en el inicio de la siguiente marca (130,6 s), como en
      // la web, no en el final de esta (138,9 s).
      expect(
        first?.trackEndsAt,
        DateTime(
          2026,
          11,
          25,
          18,
          0,
          0,
        ).add(const Duration(milliseconds: 130600)),
      );

      // 18:03:00 = 180 s: ya empezó la segunda (carátula http: se descarta).
      final second = LiveNowPlaying.parse(
        rovrJson(),
        now: DateTime(2026, 11, 25, 18, 3, 0),
      );
      expect(second?.title, 'Dos');
      expect(second?.artwork, isNull);
    });

    test('ROVR: antes de la primera pista o sin datos, programa y curador', () {
      final intro = LiveNowPlaying.parse(
        rovrJson(),
        now: DateTime(2026, 11, 25, 18, 0, 5),
      );
      expect(intro?.title, 'Saturation Point');
      expect(intro?.artist, 'soFa elsewhere');
      // Aun sin pista, la línea de tiempo y los moods del programa se ven.
      expect(intro?.moods, ['BRAIN', 'DREAM', 'CHILL']);
      expect(intro?.startedAt, isNotNull);
      expect(LiveNowPlaying.parse({'data': []}), isNull);
    });

    test('KDVS: 90.3 FM, https y su JSON en la pista', () {
      const s = RadioStation.kdvs;
      expect(s.label, '90.3 FM');
      expect(s.streamUri, isNotNull);
      expect(s.toTrack().liveInfo, isNotNull);
      expect(RadioStation.fromJson(s.toJson())?.logo, s.logo);
    });

    test('la emisora de fábrica lo trae y viaja en la pista', () {
      expect(RadioStation.shonanBeachFm.toTrack().liveInfo, isNotNull);
      final old = RadioStation.fromJson({
        'id': 'shonan-beach-fm',
        'name': 'Shonan Beach FM',
        'stream': 'https://a.test/s',
      });
      expect(old?.nowPlaying, RadioStation.shonanBeachFm.nowPlaying);
    });

    test(
      'el controlador lo muestra, manda sobre ICY y se borra al parar',
      () async {
        final engine = FakeTrackAudioEngine();
        final controller = TrackPlaybackController(
          FakeAuthRepository(user: const AuthUser(uid: 'a')),
          engine,
          'a',
          liveInfo: (url) async => const LiveNowPlaying(
            title: 'Beyond The Sea',
            artist: 'Johnny Desmond',
            program: 'MEMORY LANE AGAIN',
            artwork: 'https://a.test/c.jpg',
          ),
        );
        addTearDown(controller.dispose);
        await controller.playQueue([RadioStation.shonanBeachFm.toTrack()]);
        await Future<void>.delayed(Duration.zero);
        expect(controller.liveTitle, 'Beyond The Sea');
        expect(controller.liveArtist, 'Johnny Desmond');
        expect(controller.liveProgram, 'MEMORY LANE AGAIN');
        expect(controller.liveArtwork, 'https://a.test/c.jpg');
        // Un título ICY posterior no pisa los datos de la emisora.
        engine.liveTitleEvents.add('Otro - Distinto');
        expect(controller.liveTitle, 'Beyond The Sea');
        await controller.stop();
      },
    );
  });

  group('huso horario: cada zona tiene su señal y su programación', () {
    test('el nombre de la zona como lo escribe ROVR', () {
      String z(int h) => RadioStation.zoneName(Duration(hours: h));
      expect(z(-5), 'minus05'); // Lima
      expect(z(0), 'plus00');
      expect(z(2), 'plus02');
      expect(z(11), 'plus11');
      expect(z(-10), 'minus10');
      // Fuera de lo que tiene ROVR se ajusta.
      expect(z(14), 'plus12');
      expect(z(-12), 'minus10');
    });

    test('ROVR usa la señal del huso del teléfono; las demás, la suya', () {
      final lima = RadioStation.rovr.streamFor(const Duration(hours: -5));
      expect(
        lima.toString(),
        'https://hls-prod.rovr.live/prod/stream_minus05/llhls.m3u8',
      );
      expect(
        RadioStation.rovr.toTrack(offset: const Duration(hours: 1)).liveStream,
        Uri.parse('https://hls-prod.rovr.live/prod/stream_plus01/llhls.m3u8'),
      );
      expect(
        RadioStation.kdvs.streamFor(const Duration(hours: -5)),
        RadioStation.kdvs.streamUri,
      );
    });

    test('la plantilla de zona sobrevive al guardado', () {
      final back = RadioStation.fromJson(RadioStation.rovr.toJson());
      expect(back?.zoneStream, RadioStation.rovr.zoneStream);
      // Una plantilla sin {zone} o que no es https se ignora.
      final bad = RadioStation.fromJson({
        'id': 'otra',
        'name': 'Otra',
        'stream': 'https://a.test/s',
        'zoneStream': 'http://a.test/{zone}',
      });
      expect(bad?.zoneStream, isNull);
    });
  });

  group('metadatos dentro del audio (ID3 en HLS)', () {
    // Una etiqueta ID3 v2.4 como la de ROVR: TXXX/TrackId, TIT2, TPE1, TPUB…
    List<int> frame(String id, List<int> body) {
      final n = body.length;
      return [
        ...id.codeUnits,
        (n >> 21) & 0x7f,
        (n >> 14) & 0x7f,
        (n >> 7) & 0x7f,
        n & 0x7f,
        0,
        0,
        ...body,
      ];
    }

    List<int> text(String s, {int encoding = 3}) => [
      encoding,
      ...utf8.encode(s),
    ];

    Uint8List segment(List<List<int>> frames, {String noise = ''}) {
      final body = [for (final f in frames) ...f];
      final n = body.length;
      return Uint8List.fromList([
        ...'moof....emsg....https://aomedia.org/emsg/ID3\u0000ID3.OvenMediaEngine.ID3'
            .codeUnits,
        ...noise.codeUnits,
        ...'ID3'.codeUnits,
        4,
        0,
        0,
        (n >> 21) & 0x7f,
        (n >> 14) & 0x7f,
        (n >> 7) & 0x7f,
        n & 0x7f,
        ...body,
      ]);
    }

    test('lee título, artista, discográfica, año y el id de la pista', () {
      final info = HlsTrackInfo.fromSegment(
        segment([
          frame('TXXX', [
            0,
            ...'TrackId'.codeUnits,
            0,
            ...'abc123xyz'.codeUnits,
          ]),
          frame('TIT2', text('Remember to Remember')),
          frame('TPE1', text('Rick Holmes')),
          frame('TALB', text('12 inch')),
          frame('TPUB', text('Gold Mink')),
          frame('TYER', text('2016')),
        ]),
      );
      expect(info?.title, 'Remember to Remember');
      expect(info?.artist, 'Rick Holmes');
      expect(info?.album, '12 inch');
      expect(info?.label, 'Gold Mink');
      expect(info?.year, '2016');
      expect(info?.trackId, 'abc123xyz');
      expect(
        info?.coverUri.toString(),
        'https://rovr-prod.s3.eu-west-2.amazonaws.com/album_art/abc123xyz.jpg',
      );
    });

    test('acentos y otras codificaciones', () {
      final info = HlsTrackInfo.fromSegment(
        segment([
          frame('TIT2', text('Corazón', encoding: 3)),
          frame('TPE1', [0, ...latin1.encode('Sérgio')]),
        ]),
      );
      expect(info?.title, 'Corazón');
      expect(info?.artist, 'Sérgio');
    });

    test(
      'sin título o sin etiqueta no hay nada; un id raro no da carátula',
      () {
        expect(HlsTrackInfo.fromSegment(Uint8List(0)), isNull);
        expect(
          HlsTrackInfo.fromSegment(Uint8List.fromList(List.filled(200, 7))),
          isNull,
        );
        expect(
          HlsTrackInfo.fromSegment(
            segment([frame('TPE1', text('Sin título'))]),
          ),
          isNull,
        );
        final raro = HlsTrackInfo.fromSegment(
          segment([
            frame('TXXX', [
              0,
              ...'TrackId'.codeUnits,
              0,
              ...'../mal/..'.codeUnits,
            ]),
            frame('TIT2', text('X')),
          ]),
        );
        expect(raro?.trackId, '../mal/..');
        expect(raro?.coverUri, isNull);
      },
    );

    test('con varias etiquetas en el segmento, gana la última', () {
      final first = segment([frame('TIT2', text('Vieja'))]);
      final second = segment([frame('TIT2', text('Nueva'))]);
      expect(
        HlsTrackInfo.fromSegment(
          Uint8List.fromList([...first, ...second]),
        )?.title,
        'Nueva',
      );
    });

    test(
      'con programación, la canción es la de la programación (como la web) y no se lee el audio',
      () async {
        final engine = FakeTrackAudioEngine();
        var audioReads = 0;
        final controller = TrackPlaybackController(
          FakeAuthRepository(user: const AuthUser(uid: 'a')),
          engine,
          'a',
          liveInfo: (url) async => const LiveNowPlaying(
            title: 'Hyperballad',
            artist: 'Bjork',
            label: 'One Little Independent',
            program: 'Circadian Rhythms',
            curator: 'Mike Simonetti',
            artwork: 'https://a.test/hyperballad.jpg',
            showImage: 'https://a.test/show.jpg',
          ),
          hlsInfo: (master) async {
            audioReads++;
            return const HlsTrackInfo(title: 'Blind', artist: 'Otro');
          },
        );
        addTearDown(controller.dispose);
        await controller.playQueue([RadioStation.rovr.toTrack()]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        // La canción, el artista, la discográfica y la carátula son los de la
        // programación: lo mismo que enseña la web de la emisora.
        expect(controller.liveTitle, 'Hyperballad');
        expect(controller.liveArtist, 'Bjork');
        expect(controller.liveLabel, 'One Little Independent');
        expect(controller.liveArtwork, 'https://a.test/hyperballad.jpg');
        expect(controller.liveProgram, 'Circadian Rhythms');
        expect(controller.liveCurator, 'Mike Simonetti');
        // Y la etiqueta del audio (que va varios minutos por detrás) ni se pide.
        expect(audioReads, 0);
      },
    );

    test('sin carátula de la canción sale la foto del programa', () async {
      final controller = TrackPlaybackController(
        FakeAuthRepository(user: const AuthUser(uid: 'a')),
        FakeTrackAudioEngine(),
        'a',
        liveInfo: (url) async => const LiveNowPlaying(
          title: 'X',
          showImage: 'https://a.test/show.jpg',
        ),
      );
      addTearDown(controller.dispose);
      await controller.playQueue([RadioStation.rovr.toTrack()]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.liveArtwork, 'https://a.test/show.jpg');
    });

    test(
      'un mood espera la etiqueta del audio y no enseña nada antes',
      () async {
        final hls = Completer<HlsTrackInfo?>();
        final controller = TrackPlaybackController(
          FakeAuthRepository(user: const AuthUser(uid: 'a')),
          FakeTrackAudioEngine(),
          'a',
          hlsInfo: (master) => hls.future,
        );
        addTearDown(controller.dispose);
        final radio = RadioStation.rovr.toTrack();
        final drive = RadioMood(
          id: 'drive',
          title: 'DRIVE',
          stream: Uri.parse('https://hls.test/mood_drive/llhls.m3u8'),
          image: 'https://i.test/drive.png',
        ).toTrack(radio);
        await controller.playQueue([drive]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        // Aún sin etiqueta: ninguna canción, y la portada es la imagen del mood.
        expect(controller.liveTitle, isNull);
        expect(controller.liveArtwork, 'https://i.test/drive.png');
        hls.complete(const HlsTrackInfo(title: 'Real', artist: 'Quien suena'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(controller.liveTitle, 'Real');
        expect(controller.liveArtist, 'Quien suena');
      },
    );

    test('un mood sin programación: solo lo que dice el audio', () async {
      final engine = FakeTrackAudioEngine();
      final controller = TrackPlaybackController(
        FakeAuthRepository(user: const AuthUser(uid: 'a')),
        engine,
        'a',
        hlsInfo: (master) async => const HlsTrackInfo(
          title: 'Remember to Remember',
          artist: 'Rick Holmes',
          trackId: 'abc123xyz',
        ),
      );
      addTearDown(controller.dispose);
      final radio = RadioStation.rovr.toTrack();
      final drive = RadioMood(
        id: 'drive',
        title: 'DRIVE',
        stream: Uri.parse('https://hls.test/mood_drive/llhls.m3u8'),
        image: 'https://i.test/drive.png',
      ).toTrack(radio);
      await controller.playQueue([drive]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.liveTitle, 'Remember to Remember');
      expect(controller.liveArtist, 'Rick Holmes');
      expect(controller.liveProgram, isNull);
      // Con id de pista, su carátula.
      expect(
        controller.liveArtwork,
        'https://rovr-prod.s3.eu-west-2.amazonaws.com/album_art/abc123xyz.jpg',
      );
    });
  });

  group('moods (otras señales de la emisora)', () {
    Map<String, Object?> moodsJson() => {
      'data': [
        {
          'name': 'move',
          'hlsUrl': 'https://hls.test/mood_move.m3u8',
          'mood': {
            'title': 'MOVE',
            'order': 4,
            'squareImage': 'https://i.test/m.png',
          },
        },
        {
          'name': 'drive',
          'hlsUrl': 'https://hls.test/mood_drive.m3u8',
          'mood': {'title': 'drive', 'order': 1},
        },
        // Se descartan: flujo no https, nombre raro, sin nada.
        {'name': 'x', 'hlsUrl': 'http://hls.test/x.m3u8'},
        {'name': '../mal', 'hlsUrl': 'https://hls.test/y.m3u8'},
        'basura',
      ],
    };

    test('se leen en su orden, con título en mayúsculas', () {
      final moods = RadioMood.parseList(moodsJson());
      expect(moods.map((m) => m.id), ['drive', 'move']);
      expect(moods.first.title, 'DRIVE');
      expect(moods.last.image, 'https://i.test/m.png');
      expect(RadioMood.parseList('no'), isEmpty);
      expect(RadioMood.parseList({'data': 5}), isEmpty);
    });

    test('ROVR trae la dirección de sus moods en la pista', () {
      expect(RadioStation.rovr.toTrack().liveMoodsUrl, isNotNull);
      expect(RadioStation.shonanBeachFm.toTrack().liveMoodsUrl, isNull);
    });

    test('el mood cuelga de la emisora y se puede volver a ella', () async {
      final engine = FakeTrackAudioEngine();
      final controller = TrackPlaybackController(
        FakeAuthRepository(user: const AuthUser(uid: 'a')),
        engine,
        'a',
        moodsFetcher: (url) async => RadioMood.parseList(moodsJson()),
      );
      addTearDown(controller.dispose);
      final radio = RadioStation.rovr.toTrack();
      await controller.playQueue([radio]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.liveMoodOptions.map((m) => m.id), ['drive', 'move']);

      // Tocar un mood: otra señal, con su imagen de portada.
      final drive = controller.liveMoodOptions.first.toTrack(radio);
      await controller.playQueue([drive]);
      expect(
        engine.lastLiveAudio,
        Uri.parse('https://hls.test/mood_drive.m3u8'),
      );
      expect(controller.current?.liveParent?.id, radio.id);
      expect(controller.current?.title, 'DRIVE');
      // Las pastillas siguen ahí al cambiar de mood.
      expect(controller.liveMoodOptions, hasLength(2));

      // «Radio» vuelve a la señal de la emisora.
      await controller.playQueue([controller.current!.liveParent!]);
      expect(engine.lastLiveAudio, RadioStation.rovr.streamFor());
    });
  });

  test('el logo viaja en la pista y una lista antigua lo recupera', () {
    final track = RadioStation.shonanBeachFm.toTrack();
    expect(track.liveLogo, RadioStation.shonanBeachFm.logo);
    final old = RadioStation.fromJson({
      'id': 'shonan-beach-fm',
      'name': 'Shonan Beach FM',
      'stream': 'https://a.test/s',
    });
    expect(old?.logo, RadioStation.shonanBeachFm.logo);
    expect(RadioStation.validLogo('http://a.test/l.png'), isNull);
    expect(RadioStation.validLogo('assets/../x.png'), isNull);
    expect(RadioStation.validLogo('https://a.test/l.png'), isNotNull);
  });

  group('reanudar una radio', () {
    test('tras pausar vuelve al directo (recarga), no a donde se dejó', () async {
      final engine = FakeTrackAudioEngine();
      final controller = TrackPlaybackController(
        FakeAuthRepository(user: const AuthUser(uid: 'a')),
        engine,
        'a',
      );
      addTearDown(controller.dispose);
      await controller.playQueue([RadioStation.shonanBeachFm.toTrack()]);
      final loads = engine.plays;
      engine.lastLiveAudio = null;
      await controller.pause();
      expect(controller.phase, TrackAudioPhase.paused);
      await controller.resume();
      // Se volvió a cargar el flujo (y a darle a reproducir): el directo de ahora.
      expect(engine.lastLiveAudio, RadioStation.shonanBeachFm.streamUri);
      expect(engine.plays, greaterThan(loads));
    });

    test('un error de la señal se recupera volviendo al directo', () async {
      final engine = FakeTrackAudioEngine();
      final controller = TrackPlaybackController(
        FakeAuthRepository(user: const AuthUser(uid: 'a')),
        engine,
        'a',
      );
      addTearDown(controller.dispose);
      await controller.playQueue([RadioStation.shonanBeachFm.toTrack()]);
      engine.events.add(TrackAudioPhase.error);
      await Future<void>.delayed(Duration.zero);
      engine.lastLiveAudio = null;
      await controller.resume();
      expect(engine.lastLiveAudio, RadioStation.shonanBeachFm.streamUri);
    });
  });

  group('reproducción en directo', () {
    test('suena por liveAudio, sin resolver nada de YouTube', () async {
      final engine = FakeTrackAudioEngine();
      final controller = TrackPlaybackController(
        FakeAuthRepository(user: const AuthUser(uid: 'a')),
        engine,
        'a',
      );
      addTearDown(controller.dispose);
      final track = RadioStation.shonanBeachFm.toTrack();
      await controller.playQueue([track]);
      expect(engine.lastLiveAudio, RadioStation.shonanBeachFm.streamUri);
      expect(controller.current?.isLive, isTrue);
    });
  });

  test('la tercera ficha siempre asoma: caben dos y sobra el "peek"', () {
    for (final row in [360.0, 380.0, 411.0, 600.0]) {
      final w = RadioShelf.tileWidthFor(row);
      final thirdStart = 2 * (w + RadioShelf.gap);
      // Debe empezar dentro de la vista (si no, Flutter no la dibuja)…
      if (w < 200) expect(thirdStart, lessThan(row));
      // …y dejar ver al menos 30 dp de ella.
      if (w < 200) expect(row - thirdStart, greaterThanOrEqualTo(30));
    }
    expect(RadioShelf.tileWidthFor(2000), 200);
  });

  testWidgets('el bloque Radio muestra el nombre y el dial, y al tocar suena', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('radio_shelf');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = RadioStore.forTest(dir);
    final engine = FakeTrackAudioEngine();
    final controller = TrackPlaybackController(
      FakeAuthRepository(user: const AuthUser(uid: 'a')),
      engine,
      'a',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackPlaybackControllerProvider.overrideWithValue(controller),
        ],
        child: MaterialApp(
          home: Scaffold(body: RadioShelf(store: store)),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Radio (Auspiciado por Borregon)'), findsOneWidget);
    expect(find.text('Shonan Beach FM'), findsOneWidget);
    expect(find.text('78.9 FM'), findsOneWidget);
    await tester.tap(find.text('Shonan Beach FM'));
    await tester.pump();
    expect(engine.lastLiveAudio, RadioStation.shonanBeachFm.streamUri);
  });
}
