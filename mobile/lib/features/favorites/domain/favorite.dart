import '../../../core/network/authenticated_api_client.dart';
import '../../search/domain/catalog_track.dart';

class FavoriteItem {
  const FavoriteItem({required this.track, required this.createdAt});

  final CatalogTrack track;
  final DateTime createdAt;

  factory FavoriteItem.fromJson(Map<String, dynamic> data) {
    final track = data['track'];
    final createdAt = DateTime.tryParse(data['createdAt']?.toString() ?? '');
    if (track is! Map<String, dynamic> || createdAt == null) {
      throw const ApiFailure('Respuesta de favoritos inválida.');
    }
    return FavoriteItem(
      track: CatalogTrack.fromJson(track),
      createdAt: createdAt.toUtc(),
    );
  }
}
