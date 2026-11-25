import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import '../application/track_playback_controller.dart';
import '../domain/track_audio_engine.dart';
import '../../search/domain/catalog_track.dart';
import 'notification_art.dart';
import 'widget_bridge.dart';

// Adaptador de controles del sistema; el controlador de sesión conserva la lógica.
class MysicAudioHandler extends BaseAudioHandler {
  TrackPlaybackController? _controller;
  List<CatalogTrack> _publishedQueue = const [];
  CatalogTrack? _publishedCurrent;
  TrackAudioPhase? _publishedPhase;
  int? _publishedIndex;
  Duration? _publishedDuration;

  /// Lo último que dijo una radio en directo y que ya está en la notificación.
  String? _publishedLive;
  (PlaybackRepeat, bool, int, bool)? _publishedOptions;

  // Me gusta: el corazón del widget y de los controles. Sin cuenta enlazada no
  // hay corazón y el widget solo controla la reproducción.
  bool Function(String videoId)? _isLiked;
  Future<bool> Function(String videoId)? _toggleLike;
  Listenable? _likeChanges;
  WidgetState? _publishedWidget;
  final WidgetBridge _widget = const WidgetBridge();

  /// Conecta el corazón: [isLiked] dice si la canción ya tiene Me gusta,
  /// [toggle] lo cambia y [changes] avisa cuando cambia el conjunto.
  void bindLikes({
    required bool Function(String videoId) isLiked,
    required Future<bool> Function(String videoId) toggle,
    required Listenable changes,
  }) {
    _likeChanges?.removeListener(_onLikesChanged);
    _isLiked = isLiked;
    _toggleLike = toggle;
    _likeChanges = changes..addListener(_onLikesChanged);
    _onLikesChanged();
  }

  void _onLikesChanged() {
    _pushWidget();
    _publish();
  }

  void unbindLikes() {
    _likeChanges?.removeListener(_onLikesChanged);
    _likeChanges = null;
    _isLiked = null;
    _toggleLike = null;
  }

  static String? _videoId(CatalogTrack? track) =>
      track != null && track.id.startsWith('youtube:')
      ? track.id.substring('youtube:'.length)
      : null;

  /// Publica el estado actual en el widget de la pantalla de inicio; solo si
  /// cambió algo.
  void _pushWidget() {
    final controller = _controller;
    final current = controller?.current;
    final id = _videoId(current);
    final state = current == null || controller == null
        ? const WidgetState()
        : WidgetState(
            has: true,
            title: current.title,
            artist: current.artistName,
            art: current.thumbnailUrl,
            playing:
                controller.phase == TrackAudioPhase.playing ||
                controller.phase == TrackAudioPhase.loading,
            liked: id != null && (_isLiked?.call(id) ?? false),
          );
    if (state == _publishedWidget) return;
    _publishedWidget = state;
    unawaited(_widget.update(state));
  }

  void bind(TrackPlaybackController controller) {
    final old = _controller;
    if (old != null) old.removeListener(_publish);
    _controller = controller;
    _publishedPhase = null;
    _publishedWidget = null;
    controller.addListener(_publish);
    _publish();
  }

  void unbind(TrackPlaybackController controller) {
    if (!identical(_controller, controller)) return;
    controller.removeListener(_publish);
    _controller = null;
    _publishedQueue = const [];
    _publishedCurrent = null;
    _publishedPhase = null;
    _publishedIndex = null;
    _publishedDuration = null;
    _publishedOptions = null;
    queue.add(const []);
    _clearMediaItem();
    _pushWidget();
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle, playing: false),
    );
  }

  // La portada va cuadrada y de buen tamaño: Android la muestra grande en la
  // notificación y en la pantalla de bloqueo, y una miniatura pequeña o con
  // franjas se estira y se sale del recuadro.
  MediaItem _item(CatalogTrack track, [Duration? actualDuration, Uri? art]) {
    // Una radio en directo: lo que suena ahora, y la emisora como álbum.
    final controller = _controller;
    final now = track.isLive && identical(controller?.current, track)
        ? controller?.liveTitle
        : null;
    return MediaItem(
      id: track.id,
      title: now ?? track.title,
      artist: now == null
          ? track.artistName
          : controller?.liveArtist ?? track.title,
      album: now == null
          ? null
          : controller?.liveProgram == null
          ? track.title
          : '${track.title} · ${controller?.liveProgram}',
      duration:
          actualDuration ??
          (track.durationSeconds == null
              ? null
              : Duration(seconds: track.durationSeconds!)),
      artUri:
          art ??
          NotificationArt.immediate(
            now != null && controller?.liveArtwork != null
                ? controller?.liveArtwork
                : track.thumbnailUrl,
          ),
    );
  }

  /// Con una miniatura de vídeo, genera la portada cuadrada y, cuando está,
  /// la pone en la notificación (si la canción sigue siendo la misma).
  void _squareArt(CatalogTrack track) {
    final url = track.thumbnailUrl;
    if (url == null) return;
    unawaited(
      NotificationArt.square(url).then((art) {
        final controller = _controller;
        if (art == null ||
            controller == null ||
            !identical(controller.current, track)) {
          return;
        }
        mediaItem.add(_item(track, controller.duration, art));
      }),
    );
  }

  void _clearMediaItem() {
    // audio_service 0.18 ignora los valores null al sincronizar MediaItem con
    // Android. Publicar primero un elemento vacío reemplaza título, artista y
    // portada en la MediaSession; el null posterior conserva el contrato Dart.
    mediaItem.add(const MediaItem(id: 'mysic:idle', title: ''));
    mediaItem.add(null);
  }

  void _publish() {
    final controller = _controller;
    if (controller == null) return;
    _pushWidget();
    final current = controller.current;
    final phase = controller.phase;
    final nextQueue = controller.queue;
    final queueChanged = !listEquals(_publishedQueue, nextQueue);
    if (queueChanged) {
      queue.add(nextQueue.map(_item).toList(growable: false));
      _publishedQueue = nextQueue;
    }
    final live = controller.liveTitle == null
        ? null
        : '${controller.liveArtist}|${controller.liveTitle}|'
              '${controller.liveProgram}|${controller.liveArtwork}';
    if (!identical(current, _publishedCurrent) ||
        controller.duration != _publishedDuration ||
        live != _publishedLive) {
      if (current == null) {
        _clearMediaItem();
      } else {
        mediaItem.add(_item(current, controller.duration));
        _squareArt(current);
      }
      _publishedLive = live;
      _publishedDuration = controller.duration;
      _publishedCurrent = current;
    }
    // Publish explicit seeks and playback mode changes, while Android
    // extrapolates the position between updates.
    final likeId = _videoId(current);
    final liked = likeId != null && (_isLiked?.call(likeId) ?? false);
    final options = (
      controller.repeat,
      controller.shuffleEnabled,
      controller.seekRevision,
      liked,
    );
    if (!queueChanged &&
        _publishedPhase == phase &&
        _publishedIndex == controller.index &&
        _publishedOptions == options) {
      return;
    }
    _publishedPhase = phase;
    _publishedIndex = controller.index;
    _publishedOptions = options;
    // Controles de la notificación y de la pantalla de bloqueo: Me gusta,
    // anterior, pausa/reproducir y siguiente. La vista compacta muestra los
    // tres de reproducción; con menos de tres entra el corazón.
    final hasHeart = current != null && _toggleLike != null;
    final controls = <MediaControl>[
      if (hasHeart)
        MediaControl.custom(
          androidIcon: liked
              ? 'drawable/ic_notif_heart_on'
              : 'drawable/ic_notif_heart',
          label: liked ? 'Quitar de Me gusta' : 'Me gusta',
          name: 'like',
        ),
      // Repetir la canción, con indicador: apagado atenuado, encendido con el
      // "1". Con dos acciones propias, Android no añade el botón de aleatorio.
      // Una radio en directo no se repite, ni tiene anterior/siguiente.
      if (current != null && current.isLive != true)
        MediaControl.custom(
          androidIcon: controller.repeat == PlaybackRepeat.one
              ? 'drawable/ic_notif_repeat_on'
              : 'drawable/ic_notif_repeat',
          label: controller.repeat == PlaybackRepeat.one
              ? 'Repetir canción: activado'
              : 'Repetir canción: desactivado',
          name: 'repeat',
        ),
      if (controller.hasPrevious && current?.isLive != true)
        MediaControl.skipToPrevious,
      if (current != null)
        (phase == TrackAudioPhase.playing || phase == TrackAudioPhase.loading)
            ? MediaControl.pause
            : MediaControl.play,
      if (controller.hasNext && current?.isLive != true)
        MediaControl.skipToNext,
    ];
    final compact = <int>[
      for (final (i, c) in controls.indexed)
        if (c.action != MediaAction.custom) i,
    ].take(3).toList();
    if (hasHeart && compact.length < 3) compact.insert(0, 0);
    playbackState.add(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: compact,
        // Un directo no se puede mover: sin barra de búsqueda en el sistema.
        systemActions: current == null || current.isLive
            ? const {}
            : const {MediaAction.seek},
        processingState: switch (phase) {
          TrackAudioPhase.idle => AudioProcessingState.idle,
          TrackAudioPhase.loading => AudioProcessingState.loading,
          TrackAudioPhase.playing ||
          TrackAudioPhase.paused ||
          TrackAudioPhase.interrupted => AudioProcessingState.ready,
          TrackAudioPhase.completed => AudioProcessingState.completed,
          TrackAudioPhase.error => AudioProcessingState.error,
        },
        playing:
            phase == TrackAudioPhase.playing ||
            phase == TrackAudioPhase.loading,
        updatePosition: controller.position,
        bufferedPosition: controller.position,
        queueIndex: current == null ? null : controller.index,
        repeatMode: switch (controller.repeat) {
          PlaybackRepeat.off => AudioServiceRepeatMode.none,
          PlaybackRepeat.all => AudioServiceRepeatMode.all,
          PlaybackRepeat.one => AudioServiceRepeatMode.one,
        },
        shuffleMode: controller.shuffleEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        errorCode: phase == TrackAudioPhase.error ? 1 : null,
        errorMessage: phase == TrackAudioPhase.error
            ? 'No se pudo reproducir esta pista. Puedes reintentar o elegir la siguiente.'
            : null,
      ),
    );
  }

  @override
  Future<void> play() async => _controller?.resume();
  @override
  Future<void> pause() async => _controller?.pause();
  @override
  Future<void> stop() async => _controller?.stop();
  @override
  Future<void> skipToNext() async => _controller?.next();
  @override
  Future<void> skipToPrevious() async => _controller?.previous();
  @override
  Future<void> skipToQueueItem(int index) async => _controller?.jump(index);
  @override
  Future<void> seek(Duration position) async => _controller?.seek(position);

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == 'like') {
      final id = _videoId(_controller?.current);
      if (id != null) await _toggleLike?.call(id);
      return null;
    }
    if (name == 'repeat') {
      _controller?.toggleRepeatOne();
      return null;
    }
    return super.customAction(name, extras);
  }

  @override
  Future<void> onTaskRemoved() async {
    await _controller?.clear();
  }
}
