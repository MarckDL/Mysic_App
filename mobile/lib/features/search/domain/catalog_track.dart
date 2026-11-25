import '../../../core/network/api_failure.dart';
import '../../playback/domain/track_audio_engine.dart';

class CatalogTrack {
  const CatalogTrack({
    required this.id,
    required this.title,
    required this.artistName,
    this.durationSeconds,
    this.thumbnailUrl,
    this.licensedAudio,
    this.deviceAudio,
    this.readAudio,
    this.musicAccountTrack = false,
    this.artistId,
    this.albumId,
    this.albumName,
    this.liveStream,
    this.liveColors,
    this.liveLogo,
    this.liveInfo,
    this.liveMoodsUrl,
    this.liveParent,
  });

  /// Dónde se lee la lista de moods (otras señales) de la emisora, si tiene.
  final Uri? liveMoodsUrl;

  /// En un mood: la pista de su emisora («Radio»), para volver a ella.
  final CatalogTrack? liveParent;

  /// Dónde se lee lo que suena ahora en esta emisora (JSON `https`), si lo da.
  final Uri? liveInfo;

  /// El logo de la emisora (recurso o `https`), para su portada.
  final String? liveLogo;
  static const musicPreviewPrefix = 'music-preview:';

  /// Las radios en directo no son de YouTube: su id lleva este prefijo.
  static const livePrefix = 'radio:';

  /// El flujo de una radio en directo (`https`, con parámetros permitidos); las
  /// pistas con él no tienen duración y no pasan por el resolvedor de YouTube.
  final Uri? liveStream;

  /// Los dos colores ARGB de la emisora, para su portada en el reproductor.
  final List<int>? liveColors;

  /// Una radio en directo: sin duración, sin Me gusta, sin historial.
  bool get isLive => id.startsWith(livePrefix);

  final String id;
  bool get isMusicPreview => id.startsWith(musicPreviewPrefix);
  final String title;
  final String artistName;
  final int? durationSeconds;
  final String? thumbnailUrl;
  final Uri? licensedAudio;
  final Uri? deviceAudio;
  final TrackAudioReader? readAudio;
  final bool musicAccountTrack;

  /// Enlaces a las páginas de artista y de álbum, si el catálogo los dio.
  final String? artistId;
  final String? albumId;

  /// Nombre del álbum, si llegó con la canción.
  final String? albumName;
  bool get isConnectedAudio =>
      musicAccountTrack ||
      deviceAudio != null ||
      licensedAudio != null ||
      liveStream != null;

  /// La misma canción con su álbum, si aún no lo traía.
  CatalogTrack withAlbum(String id, String name) => albumName != null
      ? this
      : CatalogTrack(
          id: this.id,
          title: title,
          artistName: artistName,
          durationSeconds: durationSeconds,
          thumbnailUrl: thumbnailUrl,
          licensedAudio: licensedAudio,
          deviceAudio: deviceAudio,
          readAudio: readAudio,
          musicAccountTrack: musicAccountTrack,
          artistId: artistId,
          albumId: albumId ?? id,
          albumName: name,
          liveStream: liveStream,
          liveColors: liveColors,
          liveLogo: liveLogo,
          liveInfo: liveInfo,
          liveMoodsUrl: liveMoodsUrl,
          liveParent: liveParent,
        );

  factory CatalogTrack.fromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final title = data['title'];
    final artist = data['artistName'];
    final seconds = data['durationSeconds'];
    final thumbnail = data['thumbnailUrl'];
    if (id is! String ||
        !RegExp(r'^youtube:[A-Za-z0-9_-]{11}$').hasMatch(id) ||
        data['source'] != 'youtube' ||
        data['sourceId'] != id.substring(8) ||
        title is! String ||
        title.isEmpty ||
        artist is! String ||
        artist.isEmpty ||
        (seconds != null && (seconds is! int || seconds <= 0))) {
      throw const ApiFailure('Respuesta de catálogo inválida.');
    }
    final uri = thumbnail is String ? Uri.tryParse(thumbnail) : null;
    return CatalogTrack(
      id: id,
      title: title,
      artistName: artist,
      durationSeconds: seconds as int?,
      thumbnailUrl:
          uri?.scheme == 'https' && uri!.host.isNotEmpty && uri.userInfo.isEmpty
          ? thumbnail as String
          : null,
    );
  }

  String? get durationLabel {
    final seconds = durationSeconds;
    if (seconds == null) return null;
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
