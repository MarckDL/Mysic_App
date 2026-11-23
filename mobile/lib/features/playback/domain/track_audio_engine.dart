enum TrackAudioPhase {
  idle,
  loading,
  playing,
  paused,
  completed,
  error,
  interrupted,
}

/// A source could not be resolved or opened. A fresh URL may recover it.
class PlaybackSourceFailure implements Exception {
  const PlaybackSourceFailure({this.blocked = false});

  /// YouTube pide confirmar que no es un bot a esta red: ni el cliente directo
  /// ni el extractor dan la URL, y reintentar enseguida no sirve.
  final bool blocked;
}

/// A byte range from a track, supplied directly to the native player.
typedef TrackAudioReader =
    Future<TrackAudioRange> Function(int? start, int? end);

class TrackAudioRange {
  const TrackAudioRange(
    this.stream,
    this.contentType, {
    this.length,
    this.total,
    this.offset,
    required this.acceptsRanges,
  });
  final Stream<List<int>> stream;
  final String contentType;
  final int? length, total, offset;
  final bool acceptsRanges;
}

abstract interface class TrackAudioEngine {
  Stream<TrackAudioPhase> get states;
  Stream<Duration> get positions;
  Stream<Duration?> get durations;
  Duration? get duration;
  Future<void> warmUp();
  void markPlaybackRequested();
  Future<void> load(
    String sourceId,
    String token, {
    Uri? licensedAudio,
    Uri? deviceAudio,
    TrackAudioReader? readAudio,
    bool refresh = false,

    /// Duración conocida de la pista; decide si su audio se guarda en disco
    /// (los vídeos largos no se guardan).
    int? durationSeconds,
  });
  void cancelLoad();
  Future<void> prefetch(String sourceId, String token);

  /// El dedo está sobre esta canción: se empieza a resolver ya.
  void touch(String sourceId);
  void cancelPrefetch();

  /// Adelanta, sin prioridad, la resolución de varias fuentes que el usuario
  /// tiene a la vista. Un fallo no se informa: es solo una optimización.
  void warm(List<String> sourceIds);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}

/// Un motor que además puede pausar con un desvanecido. Aparte de
/// [TrackAudioEngine]: solo lo usa la pausa pedida por el usuario; las
/// interrupciones (llamada, auriculares desconectados) pausan al instante.
abstract interface class TrackAudioFade {
  /// Baja el volumen hasta cero durante [duration] y pausa. Vuelve enseguida,
  /// sin esperar al desvanecido; reanudar, cargar otra canción o detener lo
  /// cancela y devuelve el volumen.
  Future<void> pauseFading(Duration duration);
}

/// Un motor que además puede cambiar la velocidad y el tono de lo que suena.
/// Aparte de [TrackAudioEngine] para que un motor que no sepa no tenga que
/// fingirlo.
abstract interface class TrackAudioTuning {
  /// [speed] es un factor (1 = normal); [pitch], semitonos (0 = normal).
  Future<void> setTuning({required double speed, required int pitch});
}
