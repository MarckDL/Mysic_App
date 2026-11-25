import '../../search/domain/catalog_track.dart';
import 'radio_station.dart';

/// Un mood de una emisora (ROVR: DRIVE, THINK, FEEL, MOVE): otra señal en
/// directo de la misma emisora, con su propio flujo.
class RadioMood {
  const RadioMood({
    required this.id,
    required this.title,
    required this.stream,
    this.image,
  });

  /// El nombre corto del servicio (`drive`).
  final String id;

  /// Lo que se ve en la pastilla (`DRIVE`).
  final String title;
  final Uri stream;

  /// Su imagen cuadrada (`https`), que hace de portada.
  final String? image;

  /// El mood como pista del reproductor, colgada de la pista de su [parent]
  /// (la emisora «Radio»), para poder volver a ella.
  CatalogTrack toTrack(CatalogTrack parent) => CatalogTrack(
    id: '${parent.id}:$id',
    title: title,
    artistName: parent.title,
    thumbnailUrl: image,
    liveStream: stream,
    liveColors: parent.liveColors,
    liveLogo: parent.liveLogo,
    liveMoodsUrl: parent.liveMoodsUrl,
    liveParent: parent.liveParent ?? parent,
  );

  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

  /// Los moods del JSON de la emisora, en su orden. Lo que no valga se salta:
  /// nombre raro, flujo que no es `https`, o sin título.
  static List<RadioMood> parseList(Object? json) {
    final data = json is Map ? json['data'] : null;
    if (data is! List) return const [];
    final found = <(int, RadioMood)>[];
    for (final entry in data) {
      if (entry is! Map) continue;
      final name = entry['name'];
      final hls = entry['hlsUrl'];
      final stream = hls is String ? RadioStation.validStream(hls) : null;
      if (name is! String || !_id.hasMatch(name) || stream == null) continue;
      final mood = entry['mood'];
      final map = mood is Map ? mood : const {};
      final title = map['title'];
      final image = map['squareImage'];
      final order = map['order'];
      found.add((
        order is int ? order : 1 << 20,
        RadioMood(
          id: name,
          title: title is String && title.trim().isNotEmpty
              ? title.trim().toUpperCase()
              : name.toUpperCase(),
          stream: stream,
          image: image is String && RadioStation.validStream(image) != null
              ? image
              : null,
        ),
      ));
    }
    // Estable: los que empatan conservan el orden en que vinieron.
    final indexed = [for (var i = 0; i < found.length; i++) (i, found[i])];
    indexed.sort((a, b) {
      final byOrder = a.$2.$1.compareTo(b.$2.$1);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
    return [for (final (_, (_, mood)) in indexed) mood];
  }
}

/// Pide los moods de una emisora; vacío si no se pudo.
typedef RadioMoodsFetcher = Future<List<RadioMood>> Function(Uri url);
