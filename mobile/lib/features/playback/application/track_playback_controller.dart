import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../authentication/domain/auth_repository.dart';
import '../../history/application/listening_tracker.dart';
import '../../radio/domain/hls_track_info.dart';
import '../../radio/domain/live_now_playing.dart';
import '../../radio/domain/radio_mood.dart';
import '../../search/domain/catalog_track.dart';
import '../domain/track_audio_engine.dart';
import '../domain/playback_resolution.dart';

enum PlaybackRepeat { off, all, one }

/// Un lote de la radio: las canciones que se proponen y el token para pedir
/// el siguiente (null cuando YouTube Music no da más).
class RadioBatch {
  const RadioBatch(this.tracks, this.next);

  final List<CatalogTrack> tracks;
  final String? next;
}

/// Pide la radio de una canción ([videoId]) o su continuación ([cursor]).
typedef RadioFetcher =
    Future<RadioBatch> Function(String videoId, {String? cursor});

class TrackPlaybackController extends ChangeNotifier {
  TrackPlaybackController(
    this._auth,
    this._engine,
    this._uid, {
    this.history,
    this.radio,
    this.liveInfo,
    this.hlsInfo,
    this.moodsFetcher,
  }) {
    unawaited(_engine.warmUp().catchError((Object _) {}));
    _subscription = _engine.states.listen((value) {
      if (!_active) return;
      if (value == TrackAudioPhase.interrupted) {
        unawaited(pause());
        return;
      }
      if (!_eventsEnabled) return;
      // Keep the last position when a failed native source emits reset events.
      if (value == TrackAudioPhase.error) {
        _eventsEnabled = false;
      }
      if (!_wantPlayback &&
          (value == TrackAudioPhase.loading ||
              value == TrackAudioPhase.playing)) {
        return;
      }
      _set(value);
      // Temporizador «al acabar la canción»: se queda en esta, sin avanzar.
      if (value == TrackAudioPhase.completed && _sleepAtTrackEnd) {
        _sleepAtTrackEnd = false;
        _wantPlayback = false;
        notifyListeners();
        return;
      }
      // Se acabó la última pista y la radio aún no había contestado: se espera
      // su respuesta antes de dar la cola por terminada.
      if (value == TrackAudioPhase.completed &&
          !hasNext &&
          repeat == PlaybackRepeat.off &&
          _extension != null &&
          _extending) {
        final generation = _generation;
        unawaited(() async {
          await _extension;
          if (_valid(generation) && hasNext) await next();
        }());
      }
      if (value == TrackAudioPhase.completed &&
          (hasNext || repeat == PlaybackRepeat.one)) {
        final generation = _generation;
        scheduleMicrotask(() {
          if (_valid(generation)) {
            unawaited(repeat == PlaybackRepeat.one ? jump(index) : next());
          }
        });
      }
    });
    _positions = _engine.positions.listen((value) {
      if (_active && _eventsEnabled) {
        // El avance llega varias veces por segundo: solo avisa a quien
        // dibuja la posición (ver [positionListenable]), no a toda la app.
        position = value;
        _positionTicks.value = value;
      }
    });
    _durations = _engine.durations.listen((value) {
      if (_active && _eventsEnabled && value != null) {
        duration = value;
        history?.duration(value);
        notifyListeners();
      }
    });
    _liveTitles = _engine.liveTitles.listen((raw) {
      // Si la emisora da su propio JSON, ese manda (trae también la carátula).
      if (!_active || current?.isLive != true || _hasLiveInfo) return;
      final parsed = parseLiveTitle(raw, station: current!.title);
      if (parsed?.$1 == liveArtist && parsed?.$2 == liveTitle) return;
      liveArtist = parsed?.$1;
      liveTitle = parsed?.$2;
      notifyListeners();
    });
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (!_disposed && user?.uid != _uid) unawaited(clear());
    });
  }

  /// Lo que suena ahora en la radio en directo (de los metadatos del flujo);
  /// null mientras no diga nada o no sea una radio.
  String? liveArtist, liveTitle;

  /// El programa en el aire y la carátula de la canción, si la emisora los da.
  String? liveProgram, liveArtwork;

  /// Cuándo empezó y cuándo acaba la canción de la radio, si la emisora lo da
  /// (la línea de tiempo del reproductor); null si no.
  DateTime? liveStartedAt, liveEndsAt;

  /// Quién presenta el programa, la discográfica de la canción y los moods del
  /// programa (ROVR); vacíos si la emisora no los da.
  String? liveCurator, liveLabel;
  List<String> liveMoods = const [];

  /// De dónde se leen los moods de una emisora (null: sin pastillas de mood).
  final RadioMoodsFetcher? moodsFetcher;

  /// Los moods de la emisora que suena (ROVR: DRIVE, THINK…); vacío si no tiene
  /// o aún no llegaron. El reproductor los muestra como pastillas.
  List<RadioMood> liveMoodOptions = const [];
  Uri? _moodsLoadedFrom;

  /// Lee los moods de la emisora de [track] (una sola vez por emisora) y avisa
  /// al reproductor para que dibuje las pastillas.
  void _loadMoods(CatalogTrack track) {
    final url = track.liveMoodsUrl, fetch = moodsFetcher;
    if (url == null || fetch == null) {
      liveMoodOptions = const [];
      _moodsLoadedFrom = null;
      return;
    }
    if (_moodsLoadedFrom == url) return;
    _moodsLoadedFrom = url;
    unawaited(() async {
      List<RadioMood> found;
      try {
        found = await fetch(url);
      } on Object {
        found = const [];
      }
      if (!_active || _moodsLoadedFrom != url) return;
      // Sin lista, se reintentará la próxima vez que suene la emisora.
      if (found.isEmpty) _moodsLoadedFrom = null;
      liveMoodOptions = found;
      notifyListeners();
    }());
  }

  /// De dónde se lee lo que suena ahora (null: solo los metadatos del flujo).
  final LiveInfoFetcher? liveInfo;

  /// De dónde se leen los metadatos de la canción que van dentro del audio HLS
  /// (ID3 en cada segmento); null: no se leen.
  final HlsInfoFetcher? hlsInfo;
  bool _hasLiveInfo = false;
  Timer? _liveTimer, _hlsTimer;
  int _liveRun = 0;

  // Las dos fuentes de «lo que suena», que se combinan en [_applyLive]:
  // la programación de la emisora (programa, curador, línea de tiempo…) y lo
  // que dice el propio audio (título, artista, discográfica, carátula).
  LiveNowPlaying? _schedule;
  HlsTrackInfo? _hls;

  /// Cada cuánto se vuelve a preguntar la programación a la emisora.
  static const liveInfoEvery = Duration(seconds: 30);

  /// Cada cuánto se lee la etiqueta del audio (un segmento pesa ~40 KB).
  static const hlsInfoEvery = Duration(seconds: 15);

  void _stopLiveInfo() {
    _liveRun++;
    _liveTimer?.cancel();
    _liveTimer = null;
    _hlsTimer?.cancel();
    _hlsTimer = null;
    _schedule = null;
    _hls = null;
  }

  /// Une la programación y la etiqueta del audio en lo que ve el reproductor.
  /// Si el audio dice qué suena, manda: es la fuente real (la programación se
  /// calcula por la hora y puede ir desfasada unos segundos).
  void _applyLive() {
    final s = _schedule, h = _hls;
    if (s == null && h == null) return;
    _hasLiveInfo = true;
    if (s != null) {
      // La programación manda: es lo que muestra la web de la emisora (calcula
      // la canción por la hora, `ahora − inicio` sobre las marcas del programa,
      // sin leer la etiqueta del audio). Leer la del audio iba una canción por
      // detrás de la web: sus relojes difieren varios minutos.
      liveTitle = s.title;
      liveArtist = s.artist;
      liveLabel = s.label;
      liveProgram = s.program;
      liveCurator = s.curator;
      liveMoods = s.moods;
      liveStartedAt = s.startedAt;
      liveEndsAt = s.endsAt;
      // Carátula: la de la canción; si no la tiene, la foto del programa; si
      // tampoco, el logo.
      liveArtwork = s.artwork ?? s.showImage ?? current?.thumbnailUrl;
    } else if (h != null) {
      // Sin programación (los moods de ROVR): lo que dice el propio audio.
      liveTitle = h.title;
      liveArtist = h.artist;
      liveLabel = h.label;
      liveProgram = liveCurator = null;
      liveMoods = const [];
      liveStartedAt = liveEndsAt = null;
      liveArtwork = h.coverUri?.toString() ?? current?.thumbnailUrl;
    }
    notifyListeners();
  }

  /// Lee lo que suena ahora en la emisora y lo repite mientras se quiera
  /// escucharla: la programación (si la tiene) cada [liveInfoEvery], justo
  /// después de que acabe cada canción, y la etiqueta del audio cada
  /// [hlsInfoEvery].
  void _startLiveInfo(CatalogTrack track) {
    _stopLiveInfo();
    final run = _liveRun;
    final url = track.liveInfo, fetch = liveInfo;
    if (url != null && fetch != null) {
      Future<void> poll() async {
        LiveNowPlaying? info;
        if (_wantPlayback) {
          try {
            info = await fetch(url);
          } on Object {
            info = null;
          }
        }
        if (!_active || run != _liveRun) return;
        if (info != null) {
          _schedule = info;
          _applyLive();
        }
        // Con la hora de fin de la canción, se vuelve a preguntar justo
        // después (así el título cambia a tiempo); si no, cada [liveInfoEvery].
        var wait = liveInfoEvery;
        final ends = info?.trackEndsAt;
        if (ends != null) {
          // Justo después del cambio (medio segundo de margen), sin esperar
          // más de [liveInfoEvery] ni consultar más de una vez cada 2 s.
          final untilEnd =
              ends.difference(DateTime.now()) +
              const Duration(milliseconds: 500);
          if (untilEnd < wait) {
            wait = untilEnd < const Duration(seconds: 2)
                ? const Duration(seconds: 2)
                : untilEnd;
          }
        }
        _liveTimer = Timer(wait, () => unawaited(poll()));
      }

      unawaited(poll());
    }

    // La etiqueta del audio solo se lee si no hay programación (los moods): con
    // ella, la canción sale de la programación, como en la web de la emisora.
    final stream = track.liveStream, readHls = hlsInfo;
    if (url == null &&
        stream != null &&
        readHls != null &&
        stream.path.endsWith('.m3u8')) {
      Future<void> pollHls() async {
        HlsTrackInfo? info;
        if (_wantPlayback) {
          try {
            info = await readHls(stream);
          } on Object {
            info = null;
          }
        }
        if (!_active || run != _liveRun) return;
        // Sin etiqueta (entre pistas, o una señal sin ella) se conserva la
        // anterior: mejor la última canción que un hueco.
        if (info != null) {
          _hls = info;
          _applyLive();
        }
        _hlsTimer = Timer(hlsInfoEvery, () => unawaited(pollHls()));
      }

      unawaited(pollHls());
    }
  }

  /// Separa el `StreamTitle` de una radio («Artista - Título») en
  /// (artista, título). Devuelve null si no hay canción identificada: vacío,
  /// el propio nombre de la emisora o avisos como «offline». Sin separador,
  /// todo es el título.
  static (String?, String)? parseLiveTitle(
    String? raw, {
    required String station,
  }) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty || text.length > 200) return null;
    final lower = text.toLowerCase();
    if (lower == station.toLowerCase() ||
        lower.endsWith(' - offline') ||
        lower == 'offline' ||
        lower.endsWith(' - live') ||
        lower == 'unknown') {
      return null;
    }
    final cut = text.indexOf(' - ');
    if (cut <= 0 || cut + 3 >= text.length) return (null, text);
    final artist = text.substring(0, cut).trim();
    final title = text.substring(cut + 3).trim();
    // «Emisora - algo»: el prefijo es la emisora, no un artista.
    if (artist.toLowerCase() == station.toLowerCase()) {
      return title.isEmpty ? null : (null, title);
    }
    return (artist, title);
  }

  bool get isDemoTrack => current?.id == demoTrack.id;
  bool get isBundledTrack => isDemoTrack || current?.isMusicPreview == true;
  MusicListenCallback? _onPreviewListened;
  MusicListenCallback? Function()? _listenForTrack;

  static const demoTrack = CatalogTrack(
    id: 'demo:${PlaybackResolution.demoId}',
    title: 'Audio de prueba',
    artistName: 'Mysic',
    durationSeconds: 8,
  );

  final ListeningTracker? history;
  final AuthRepository _auth;
  final TrackAudioEngine _engine;
  final String _uid;
  late final StreamSubscription<TrackAudioPhase> _subscription;
  late final StreamSubscription<Duration> _positions;
  late final StreamSubscription<Duration?> _durations;
  late final StreamSubscription<String?> _liveTitles;
  late final StreamSubscription<AuthUser?> _authSubscription;
  final List<CatalogTrack> _queue = [];
  List<CatalogTrack> get queue => List.unmodifiable(_queue);

  /// Máximo de pistas en la cola (las ya oídas, la actual y las que siguen).
  static const maxQueue = 500;

  /// Pistas ya oídas que se conservan atrás para poder volver a ellas.
  static const maxHistory = 200;

  /// Con cuántas pistas por delante se pide más autoplay.
  static const autoplayThreshold = 2;

  /// Cuántas canciones de la radio se añaden por lote.
  static const autoplayBatch = 20;

  /// De dónde salen las canciones del autoplay; null sin sesión.
  final RadioFetcher? radio;

  /// Si al acercarse el final de la cola se añaden canciones parecidas (la
  /// radio de YouTube Music). Con repetir activado no hay autoplay.
  bool autoplay = true;

  /// Las pistas que añadió la radio, no el usuario: van detrás de lo que el
  /// usuario puso en cola y se distinguen en la lista.
  final Set<String> _autoIds = {};
  bool isAutoplayTrack(CatalogTrack track) => _autoIds.contains(track.id);

  /// Hay un proveedor de radio (con sesión de YouTube Music).
  bool get hasRadio => radio != null;

  bool _extending = false;
  bool get loadingAutoplay => _extending;
  String? _radioCursor;
  bool _radioExhausted = false;

  /// Cambia cada vez que la cola se reemplaza o se vacía; una respuesta de la
  /// radio pedida para una cola anterior se descarta.
  var _queueRevision = 0;

  /// Cuántas pistas siguen a la actual.
  int get upcomingCount =>
      index < 0 ? _queue.length : _queue.length - index - 1;

  void setAutoplay(bool value) {
    if (autoplay == value) return;
    autoplay = value;
    if (!value) {
      // Lo que la radio había propuesto y aún no suena se quita.
      _dropAutoplayAhead();
    } else {
      _maybeExtend();
    }
    notifyListeners();
  }

  void _dropAutoplayAhead() {
    final keep = index + 1;
    for (var i = _queue.length - 1; i >= keep && i >= 0; i--) {
      if (_autoIds.contains(_queue[i].id)) _queue.removeAt(i);
    }
    _autoIds.removeWhere((id) => !_queue.any((t) => t.id == id));
    _radioCursor = null;
    _radioExhausted = false;
    _engine.cancelPrefetch();
  }

  /// Pide a la radio más canciones cuando quedan pocas por delante, las añade
  /// al final (sin repetir ninguna ya en la cola) y las marca como autoplay.
  void _maybeExtend() {
    final fetch = radio;
    final now = current;
    if (fetch == null ||
        !autoplay ||
        _extending ||
        _radioExhausted ||
        !_active ||
        now == null ||
        !now.musicAccountTrack ||
        now.isMusicPreview ||
        repeat != PlaybackRepeat.off ||
        upcomingCount > autoplayThreshold ||
        _queue.length >= maxQueue) {
      return;
    }
    _extending = true;
    final revision = _queueRevision;
    final cursor = _radioCursor;
    // La radio sigue desde la última pista de la cola: así lo que se añade
    // continúa lo que ya estaba por delante.
    final seed = _queue.last.id.substring(8);
    _extension = (() async {
      try {
        final batch = await fetch(seed, cursor: cursor);
        if (!_active || revision != _queueRevision) return;
        final known = {for (final t in _queue) t.id};
        final fresh = <CatalogTrack>[];
        for (final track in batch.tracks) {
          if (fresh.length >= autoplayBatch) break;
          if (!track.musicAccountTrack ||
              !_validTrack(track) ||
              !known.add(track.id)) {
            continue;
          }
          fresh.add(track);
        }
        _radioCursor = batch.next;
        if (fresh.isEmpty) {
          // Con cursor, se vuelve a empezar desde otra semilla la próxima vez;
          // sin él no hay nada más que dar.
          if (batch.next == null) _radioExhausted = true;
          return;
        }
        final room = maxQueue - _queue.length;
        final take = fresh.take(room).toList();
        final hadNext = upcomingCount > 0;
        _queue.addAll(take);
        _autoIds.addAll(take.map((t) => t.id));
        if (!hadNext && index >= 0 && _wantPlayback) _prepareAdjacent();
      } on Object {
        // Sin red o sin sesión la cola sigue como está; se reintenta al cambiar
        // de pista.
      } finally {
        _extending = false;
        if (_active && revision == _queueRevision) notifyListeners();
      }
    })();
  }

  /// La petición de autoplay en curso, si hay.
  Future<void>? _extension;

  /// Cuántas pistas por delante se dejan listas (su URL y el primer tramo de
  /// su audio), además de la anterior.
  static const prepareAhead = 3;

  /// Deja preparadas las pistas de alrededor de la actual para que cambiar de
  /// pista, o volver a la anterior, no espere a YouTube: la siguiente se
  /// precarga con prioridad y las tres siguientes y la anterior se calientan
  /// en segundo plano. Solo las que pasan por el resolvedor; con «solo
  /// descargadas» el motor no abre ninguna conexión.
  void _prepareAdjacent() {
    if (index < 0 || !_wantPlayback) return;
    _prefetchNext();
    final ids = <String>[];
    void add(int i) {
      if (i < 0 || i >= _queue.length) return;
      final track = _queue[i];
      if (track.id != demoTrack.id &&
          !track.isMusicPreview &&
          track.deviceAudio == null &&
          track.licensedAudio == null &&
          track.readAudio == null &&
          track.liveStream == null &&
          _validTrack(track)) {
        ids.add(track.id.substring(8));
      }
    }

    for (var i = index + 1; i <= index + prepareAhead; i++) {
      add(i);
    }
    add(index - 1);
    if (ids.isNotEmpty) _engine.warm(ids);
  }

  void _prefetchNext() {
    if (index < 0 || !_wantPlayback || index + 1 >= _queue.length) return;
    final next = _queue[index + 1];
    if (next.id == demoTrack.id ||
        next.isMusicPreview ||
        next.deviceAudio != null ||
        next.licensedAudio != null ||
        next.readAudio != null ||
        next.liveStream != null) {
      return;
    }
    unawaited(
      _engine
          .prefetch(next.id.substring(8), _sourceToken)
          .catchError((Object _) {}),
    );
  }

  /// Quita de atrás las pistas ya oídas que pasan de [maxHistory].
  void _trimHistory() {
    final extra = index - maxHistory;
    if (extra <= 0) return;
    final removed = _queue.sublist(0, extra);
    _queue.removeRange(0, extra);
    _originalOrder.removeWhere(removed.contains);
    _autoIds.removeAll(removed.map((t) => t.id));
    index -= extra;
  }

  int index = -1;
  CatalogTrack? get current =>
      index >= 0 && index < _queue.length ? _queue[index] : null;
  PlaybackRepeat repeat = PlaybackRepeat.off;
  bool shuffleEnabled = false;
  final List<CatalogTrack> _originalOrder = [];
  void cycleRepeat() {
    if (!_active) return;
    repeat = PlaybackRepeat
        .values[(repeat.index + 1) % PlaybackRepeat.values.length];
    notifyListeners();
  }

  /// Repetir la canción que suena: activa o desactiva el modo "una" (el
  /// botón de la notificación y de la pantalla de bloqueo).
  void toggleRepeatOne() {
    if (!_active) return;
    repeat = repeat == PlaybackRepeat.one
        ? PlaybackRepeat.off
        : PlaybackRepeat.one;
    notifyListeners();
  }

  void toggleShuffle() {
    if (!_active || _queue.length < 2) return;
    final selected = current;
    shuffleEnabled = !shuffleEnabled;
    if (shuffleEnabled) {
      _originalOrder
        ..clear()
        ..addAll(_queue);
      // Solo se baraja lo que viene después: lo ya oído y la pista actual se
      // quedan donde están.
      final head = _queue.sublist(0, index < 0 ? 0 : index + 1);
      final upcoming = _queue.sublist(index < 0 ? 0 : index + 1)..shuffle();
      _queue
        ..clear()
        ..addAll([...head, ...upcoming]);
    } else {
      final remaining = _queue.toList();
      final restored = <CatalogTrack>[];
      for (final track in _originalOrder) {
        final match = remaining.indexWhere((item) => identical(item, track));
        if (match >= 0) restored.add(remaining.removeAt(match));
      }
      _queue
        ..clear()
        ..addAll([...restored, ...remaining]);
      _originalOrder.clear();
    }
    index = selected == null
        ? -1
        : _queue.indexWhere((track) => identical(track, selected));
    _engine.cancelPrefetch();
    notifyListeners();
  }

  bool get hasNext =>
      index >= 0 && (index + 1 < _queue.length || repeat == PlaybackRepeat.all);
  bool get hasPrevious => index > 0;
  bool _eventsEnabled = false;
  bool _wantPlayback = false;
  bool _autoRecoveryUsed = false;
  bool _disposed = false;
  bool get _active => !_disposed && _auth.currentUser?.uid == _uid;
  TrackAudioPhase phase = TrackAudioPhase.idle;

  /// La última pista falló porque YouTube pide confirmar que no es un bot a
  /// esta red: las canciones descargadas siguen sonando, las nuevas no.
  bool sourceBlocked = false;
  String? sourceId;
  Duration position = Duration.zero;

  final _positionTicks = ValueNotifier<Duration>(Duration.zero);

  /// Avisa con cada avance de la reproducción. Los saltos, los cambios de
  /// pista y de estado siguen avisando por el propio controlador, así que
  /// quien dibuja la posición debe escuchar los dos.
  ValueListenable<Duration> get positionListenable => _positionTicks;
  Duration? duration;
  int _seekRevision = 0;
  int get seekRevision => _seekRevision;
  int _generation = 0;
  Future<void> _preparation = Future.value();
  bool _valid(int generation) => _active && generation == _generation;
  Future<void> _stopEngine() {
    // Serialize native stops, but never make a selection wait for old resolution.
    return _preparation = _preparation
        .catchError((Object _) {})
        .then((_) => _engine.stop());
  }

  void _set(TrackAudioPhase value) {
    history?.phase(value);
    phase = value;
    if (!_disposed) notifyListeners();
  }

  bool _validTrack(CatalogTrack track) =>
      track.id == demoTrack.id ||
      track.isMusicPreview ||
      (track.isLive && track.liveStream != null) ||
      RegExp(r'^youtube:[A-Za-z0-9_-]{11}$').hasMatch(track.id);

  Future<void> start(String id) => playTrack(
    CatalogTrack(id: 'youtube:$id', title: id, artistName: 'YouTube'),
  );

  Future<void> playTrack(CatalogTrack track) async {
    if (!_active ||
        track.isMusicPreview ||
        _onPreviewListened != null ||
        (_queue.any((t) => t.isConnectedAudio) && !track.isConnectedAudio)) {
      return;
    }
    if (!_validTrack(track)) {
      _set(TrackAudioPhase.error);
      return;
    }
    var target = _queue.indexWhere((item) => item.id == track.id);
    if (target < 0) {
      if (_queue.length >= maxQueue) return;
      _queue.add(track);
      target = _queue.length - 1;
    } else {
      _queue[target] = track;
    }
    await jump(target);
  }

  /// El resolvedor de Android no usa el token (el audio se resuelve en el
  /// teléfono); solo exige que no esté vacío. Con la sesión de YouTube Music no
  /// hay token de ningún servidor, así que se usa un valor fijo.
  static const _sourceToken = 'device';

  Future<void> prefetchTrack(CatalogTrack track) async {
    if (!_active ||
        !_validTrack(track) ||
        track.isConnectedAudio ||
        track.id == demoTrack.id ||
        track.isMusicPreview ||
        _onPreviewListened != null) {
      return;
    }
    _engine.cancelPrefetch();
    final generation = _generation;
    if (!_valid(generation)) return;
    await _engine.prefetch(track.id.substring(8), _sourceToken);
  }

  void cancelPrefetch() => _engine.cancelPrefetch();

  /// Máximo de canciones a la vista cuya fuente se adelanta de una vez.
  static const warmLimit = 12;

  /// Adelanta la resolución de las primeras canciones que el usuario tiene a
  /// la vista, para que tocar una no espere a resolverla. Solo cuentan las
  /// que pasan por el resolvedor: las que traen archivo o lector propio no
  /// tienen nada que adelantar.
  void warmTracks(Iterable<CatalogTrack> tracks) {
    if (!_active) return;
    final ids = <String>{
      for (final track in tracks)
        if (_validTrack(track) &&
            track.id != demoTrack.id &&
            !track.isMusicPreview &&
            track.deviceAudio == null &&
            track.licensedAudio == null &&
            track.readAudio == null &&
            track.liveStream == null)
          track.id.substring(8),
    };
    if (ids.isNotEmpty) _engine.warm(ids.take(warmLimit).toList());
  }

  /// El dedo acaba de tocar [track] (aún no se ha levantado): se empieza a
  /// resolver su audio ya. Si luego se toca de verdad, la reproducción se une a
  /// esa resolución en vez de empezar de cero.
  void touchTrack(CatalogTrack track) {
    if (!_active ||
        !_validTrack(track) ||
        track.id == demoTrack.id ||
        track.isMusicPreview ||
        track.deviceAudio != null ||
        track.licensedAudio != null ||
        track.readAudio != null ||
        track.liveStream != null) {
      return;
    }
    _engine.touch(track.id.substring(8));
  }

  void enqueue(CatalogTrack track) {
    if (!_active ||
        track.isMusicPreview ||
        _onPreviewListened != null ||
        (_queue.any((t) => t.isConnectedAudio) && !track.isConnectedAudio) ||
        !_validTrack(track) ||
        _queue.length >= maxQueue ||
        _queue.any((item) => item.id == track.id)) {
      return;
    }
    _engine.cancelPrefetch();
    _queue.add(track);
    notifyListeners();
  }

  bool queueConnected(
    Iterable<CatalogTrack> tracks, {
    required bool next,
    MusicListenCallback? Function()? listenForTrack,
  }) {
    if (!_active || _queue.any((t) => !t.isConnectedAudio)) return false;
    final playing = current;
    final existing = _queue.map((t) => t.id).toSet();
    final incoming = <String, CatalogTrack>{};
    var slots = maxQueue - _queue.length;
    for (final track in tracks) {
      if (!track.isConnectedAudio ||
          !_validTrack(track) ||
          track.id == playing?.id ||
          incoming.containsKey(track.id)) {
        continue;
      }
      if (!existing.contains(track.id)) {
        if (slots == 0) continue;
        slots--;
      }
      incoming[track.id] = track;
    }
    if (incoming.isEmpty) return false;
    // Lo que el usuario añade pasa a ser suyo: deja de ser autoplay.
    _autoIds.removeAll(incoming.keys);
    int insert(List<CatalogTrack> list, {required bool skipAutoplay}) {
      list.removeWhere((track) => incoming.containsKey(track.id));
      final selected = playing == null ? -1 : list.indexOf(playing);
      var at = list.length;
      if (next && selected >= 0) {
        at = selected + 1;
      } else if (skipAutoplay) {
        // «Añadir a la cola» va al final de lo del usuario, delante de lo que
        // propuso la radio.
        var firstAuto = list.length;
        while (firstAuto > selected + 1 &&
            _autoIds.contains(list[firstAuto - 1].id)) {
          firstAuto--;
        }
        at = firstAuto;
      }
      list.insertAll(at, incoming.values);
      return selected;
    }

    index = insert(_queue, skipAutoplay: true);
    if (shuffleEnabled) insert(_originalOrder, skipAutoplay: false);
    _listenForTrack = listenForTrack;
    _engine.cancelPrefetch();
    _prepareAdjacent();
    notifyListeners();
    return true;
  }

  /// Mueve la pista de [from] a [to] (posiciones de [queue]) sin interrumpir
  /// el audio. La pista actual se puede mover; el puntero la sigue.
  void move(int from, int to) {
    if (!_active ||
        from < 0 ||
        to < 0 ||
        from >= _queue.length ||
        to >= _queue.length ||
        from == to) {
      return;
    }
    final playing = current;
    final track = _queue.removeAt(from);
    _queue.insert(to, track);
    // Al arrastrar una propuesta de la radio hacia lo del usuario (o al
    // revés) cambia de dueño según donde cae.
    final before = to > 0 ? _queue[to - 1] : null;
    final after = to + 1 < _queue.length ? _queue[to + 1] : null;
    if (_autoIds.contains(track.id)) {
      if (before != null &&
          !_autoIds.contains(before.id) &&
          after != null &&
          !_autoIds.contains(after.id)) {
        _autoIds.remove(track.id);
      }
    }
    index = playing == null ? -1 : _queue.indexOf(playing);
    _engine.cancelPrefetch();
    _prepareAdjacent();
    notifyListeners();
  }

  /// Quita todo lo que viene después de la pista actual.
  void clearUpcoming() {
    if (!_active || index < 0 || index + 1 >= _queue.length) return;
    final removed = _queue.sublist(index + 1);
    _queue.removeRange(index + 1, _queue.length);
    _originalOrder.removeWhere(removed.contains);
    _autoIds.removeAll(removed.map((t) => t.id));
    _radioCursor = null;
    _engine.cancelPrefetch();
    notifyListeners();
    _maybeExtend();
  }

  Future<void> playQueue(
    List<CatalogTrack> tracks, {
    int initialIndex = 0,
    bool shuffled = false,
    MusicListenCallback? onPreviewListened,
    MusicListenCallback? Function()? listenForTrack,
  }) async {
    if (!_active ||
        tracks.isEmpty ||
        tracks.length > maxQueue ||
        (tracks.any((t) => t.isConnectedAudio) &&
            tracks.any((t) => !t.isConnectedAudio)) ||
        tracks.any(
          (track) =>
              !_validTrack(track) ||
              track.isMusicPreview != (onPreviewListened != null),
        ) ||
        initialIndex < 0 ||
        initialIndex >= tracks.length) {
      return;
    }
    history?.finish();
    _onPreviewListened = onPreviewListened;
    _listenForTrack = listenForTrack;
    // Una cola nueva: lo que la radio propuso para la anterior no vale.
    _queueRevision++;
    _autoIds.clear();
    _radioCursor = null;
    _radioExhausted = false;
    shuffleEnabled = shuffled && tracks.length > 1;
    _originalOrder.clear();
    _queue
      ..clear()
      ..addAll(tracks);
    if (shuffleEnabled) {
      _originalOrder.addAll(tracks);
      _queue.shuffle();
    }
    await jump(shuffleEnabled ? 0 : initialIndex);
  }

  Future<void> jump(int target) => _loadTrack(target);

  Future<void>? _recoverSource() {
    if (!_wantPlayback || _autoRecoveryUsed || current == null) return null;
    _autoRecoveryUsed = true;
    // Una radio vuelve al directo: no hay posición a la que regresar.
    return _loadTrack(
      index,
      resumeAt: current!.isLive ? Duration.zero : position,
      refresh: true,
    );
  }

  Future<void> _loadTrack(
    int target, {
    Duration? resumeAt,
    bool refresh = false,
  }) async {
    if (!_active || target < 0 || target >= _queue.length) return;
    // Only an explicit selection starts a new listening session. Retrying a
    // failed source keeps both its accumulated listening time and position.
    if (resumeAt == null) {
      final track = _queue[target];
      final listen = track.isConnectedAudio
          ? _listenForTrack?.call()
          : _onPreviewListened;
      if (track.id == demoTrack.id ||
          (track.isConnectedAudio && listen == null)) {
        history?.finish();
      } else {
        history?.begin(track, onMusicListen: listen);
      }
      _autoRecoveryUsed = false;
    }
    _wantPlayback = true;
    _engine.cancelLoad();
    _engine.markPlaybackRequested();
    final generation = ++_generation;
    _eventsEnabled = false;
    index = target;
    // Lo que sonaba en la radio anterior ya no vale.
    liveArtist = liveTitle = liveProgram = liveArtwork = null;
    liveStartedAt = liveEndsAt = null;
    liveCurator = liveLabel = null;
    liveMoods = const [];
    // Un mood no trae «ahora suena»: su imagen cuadrada hace de portada.
    if (current?.isLive == true) liveArtwork = current!.thumbnailUrl;
    _hasLiveInfo = false;
    _stopLiveInfo();
    sourceId = isBundledTrack
        ? PlaybackResolution.demoId
        : current!.isLive
        ? current!.id
        : current!.id.substring(8);
    final requestedId = sourceId!;
    position = resumeAt ?? Duration.zero;
    duration = current!.durationSeconds == null
        ? null
        : Duration(seconds: current!.durationSeconds!);
    var stage = 'stop';
    try {
      final stopped = _stopEngine();
      _set(TrackAudioPhase.loading);
      await stopped;
      if (!_valid(generation)) return;
      stage = 'audio-load';
      sourceBlocked = false;
      await _engine.load(
        requestedId,
        _sourceToken,
        refresh: refresh,
        licensedAudio: current!.licensedAudio,
        deviceAudio: current!.deviceAudio,
        readAudio: current!.readAudio,
        liveAudio: current!.liveStream,
        durationSeconds: current!.durationSeconds,
      );
      if (!_valid(generation)) return;
      final actualDuration = _engine.duration;
      if (actualDuration != null && actualDuration > Duration.zero) {
        history?.duration(actualDuration);
        duration = actualDuration;
      }
      if (resumeAt != null && resumeAt > Duration.zero) {
        final limit = duration;
        final destination = limit != null && resumeAt > limit
            ? limit
            : resumeAt;
        await _engine.seek(destination);
        if (!_valid(generation)) return;
        position = destination;
      }
      _eventsEnabled = true;
      if (!_wantPlayback) {
        _set(TrackAudioPhase.paused);
        return;
      }
      if (current!.isLive) {
        _startLiveInfo(current!);
        _loadMoods(current!);
      } else {
        liveMoodOptions = const [];
        _moodsLoadedFrom = null;
      }
      await _engine.play();
      if (_valid(generation) && _wantPlayback) {
        _trimHistory();
        _prepareAdjacent();
        _maybeExtend();
      }
    } catch (error) {
      if (_valid(generation)) {
        if (kDebugMode) debugPrint('audio_start_failed stage=$stage');
        // El motivo llega al reproductor para explicarlo (y no insistir).
        sourceBlocked = error is PlaybackSourceFailure && error.blocked;
        final recovery = error is PlaybackSourceFailure && !refresh
            ? _recoverSource()
            : null;
        if (recovery != null) {
          await recovery;
          return;
        }
        _eventsEnabled = false;
        try {
          await _stopEngine();
        } catch (_) {}
        if (_valid(generation)) _set(TrackAudioPhase.error);
      }
    }
  }

  Future<void> next() async {
    if (hasNext) await jump(index + 1 < _queue.length ? index + 1 : 0);
  }

  /// Como Limusic: con más de 3 s sonando, «anterior» reinicia la pista; solo
  /// al principio pasa a la anterior.
  Future<void> previous() async {
    if (current != null && position > const Duration(seconds: 3)) {
      await jump(index);
      return;
    }
    if (hasPrevious) await jump(index - 1);
  }

  Future<void> removeDeviceAudio(Uri audio) async {
    if (!_active || !_queue.any((track) => track.deviceAudio == audio)) return;
    final selected = current;
    final selectedRemoved = selected?.deviceAudio == audio;
    _engine.cancelPrefetch();
    _queue.removeWhere((track) => track.deviceAudio == audio);
    _originalOrder.removeWhere((track) => track.deviceAudio == audio);
    index = selected == null ? -1 : _queue.indexOf(selected);
    if (_queue.isEmpty) {
      await clear();
    } else if (selectedRemoved) {
      sourceId = null;
      position = Duration.zero;
      duration = null;
      await stop();
    } else {
      notifyListeners();
    }
  }

  void remove(int target) {
    if (!_active || target < 0 || target >= _queue.length || target == index) {
      return;
    }
    _engine.cancelPrefetch();
    final removed = _queue.removeAt(target);
    _autoIds.remove(removed.id);
    if (target < index) index--;
    _prepareAdjacent();
    notifyListeners();
    _maybeExtend();
  }

  /// Lo que dura el desvanecido al pausar.
  static const pauseFade = Duration(milliseconds: 500);

  Future<void> pause() async {
    if (!_active) return;
    if (phase == TrackAudioPhase.error) return;
    _wantPlayback = false;
    if (!_eventsEnabled &&
        (phase == TrackAudioPhase.loading || phase == TrackAudioPhase.paused)) {
      await stop();
      return;
    }
    final generation = _generation;
    final Object engine = _engine;
    // Al pausar el usuario la canción se desvanece en medio segundo; solo si
    // estaba sonando. Las interrupciones pausan por su lado, al instante.
    if (engine is TrackAudioFade && phase == TrackAudioPhase.playing) {
      await engine.pauseFading(pauseFade);
    } else {
      await _engine.pause();
    }
    if (_valid(generation) &&
        !_wantPlayback &&
        phase != TrackAudioPhase.error) {
      _set(TrackAudioPhase.paused);
    }
  }

  Future<void> resume() async {
    if (!_active) return;
    // Una radio en directo no se reanuda donde se dejó: la ventana del directo
    // ya avanzó (el reproductor daría un error de «detrás del directo»). Se
    // vuelve a sintonizar y suena lo que está sonando ahora.
    if (current?.isLive == true &&
        phase != TrackAudioPhase.loading &&
        phase != TrackAudioPhase.playing) {
      await _loadTrack(index);
      return;
    }
    if (phase == TrackAudioPhase.error && current != null) {
      await _loadTrack(index, resumeAt: position, refresh: true);
    } else if (phase == TrackAudioPhase.paused) {
      _wantPlayback = true;
      if (_eventsEnabled) {
        await _engine.play();
      } else {
        _set(TrackAudioPhase.loading);
      }
    } else if (current != null &&
        phase != TrackAudioPhase.loading &&
        phase != TrackAudioPhase.playing) {
      await jump(index);
    }
  }

  bool get canSeek =>
      _active &&
      current != null &&
      (duration ?? Duration.zero) > Duration.zero &&
      _eventsEnabled &&
      phase != TrackAudioPhase.loading &&
      phase != TrackAudioPhase.error;

  Future<void> seek(Duration target) async {
    if (!canSeek || target.isNegative) return;
    final limit = duration!;
    final bounded = target > limit ? limit : target;
    final generation = _generation;
    history?.phase(TrackAudioPhase.paused);
    try {
      await _engine.seek(bounded);
      if (_valid(generation) && _eventsEnabled) {
        position = bounded;
        _seekRevision++;
        notifyListeners();
      }
    } finally {
      if (_valid(generation)) history?.phase(phase);
    }
  }

  Future<void> stop() async {
    history?.finish();
    _engine.cancelPrefetch();
    _engine.cancelLoad();
    ++_generation;
    _wantPlayback = false;
    _eventsEnabled = false;
    _stopLiveInfo();
    if (!_disposed) {
      final stopped = _stopEngine();
      _set(TrackAudioPhase.idle);
      try {
        await stopped;
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    _engine.cancelPrefetch();
    _queueRevision++;
    _autoIds.clear();
    _radioCursor = null;
    _radioExhausted = false;
    _queue.clear();
    _onPreviewListened = null;
    _listenForTrack = null;
    _originalOrder.clear();
    shuffleEnabled = false;
    repeat = PlaybackRepeat.off;
    index = -1;
    sourceId = null;
    position = Duration.zero;
    duration = null;
    await stop();
  }

  // ---- Velocidad y tono ----
  /// Factor de velocidad (1 = normal), de 0,2 a 2 en pasos de 0,1.
  double speed = 1;

  /// Tono en semitonos, de -12 a 12.
  int pitch = 0;

  bool get canTune => _engine is TrackAudioTuning;

  /// Cambia la velocidad o el tono; lo que va a null se queda como estaba.
  Future<void> setTuning({double? speed, int? pitch}) async {
    final Object engine = _engine;
    if (engine is! TrackAudioTuning) return;
    this.speed = (((speed ?? this.speed) * 10).round() / 10).clamp(.2, 2.0);
    this.pitch = (pitch ?? this.pitch).clamp(-12, 12);
    notifyListeners();
    try {
      await engine.setTuning(speed: this.speed, pitch: this.pitch);
    } on Object {
      // Un motor que no puede aplicar el cambio sigue sonando como estaba.
    }
  }

  // ---- Temporizador de apagado ----

  DateTime? _sleepAt;
  bool _sleepAtTrackEnd = false;
  Timer? _sleepTimer;

  /// Cuándo se pausará; null si no hay cuenta atrás.
  DateTime? get sleepAt => _sleepAt;

  /// Se pausará al terminar la canción que suena.
  bool get sleepAtTrackEnd => _sleepAtTrackEnd;

  bool get sleepActive => _sleepAt != null || _sleepAtTrackEnd;

  /// Minutos que quedan, redondeados hacia arriba; 0 si no hay cuenta atrás.
  int get sleepMinutesLeft {
    final at = _sleepAt;
    if (at == null) return 0;
    final seconds = at.difference(DateTime.now()).inSeconds;
    return seconds <= 0 ? 1 : (seconds + 59) ~/ 60;
  }

  /// Pausa la reproducción dentro de [minutes].
  void setSleepTimer(int minutes) {
    if (minutes <= 0) return;
    _sleepTimer?.cancel();
    _sleepAtTrackEnd = false;
    _sleepAt = DateTime.now().add(Duration(minutes: minutes));
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      _sleepAt = null;
      _sleepTimer = null;
      if (_disposed) return;
      notifyListeners();
      unawaited(pause());
    });
    notifyListeners();
  }

  /// Pausa la reproducción cuando termine la canción que suena.
  void sleepAfterTrack() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAt = null;
    _sleepAtTrackEnd = true;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAt = null;
    _sleepAtTrackEnd = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _sleepTimer?.cancel();
    history?.dispose();
    _disposed = true;
    _engine.cancelPrefetch();
    ++_generation;
    _queue.clear();
    _onPreviewListened = null;
    _listenForTrack = null;
    _originalOrder.clear();
    shuffleEnabled = false;
    repeat = PlaybackRepeat.off;
    index = -1;
    sourceId = null;
    unawaited(_subscription.cancel());
    unawaited(_positions.cancel());
    unawaited(_durations.cancel());
    unawaited(_liveTitles.cancel());
    _stopLiveInfo();
    unawaited(_authSubscription.cancel());
    unawaited(_engine.dispose());
    super.dispose();
  }
}
