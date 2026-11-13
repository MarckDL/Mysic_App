import '../../search/domain/catalog_track.dart';
import '../../../core/network/authenticated_api_client.dart';

class FavoriteItem {
  const FavoriteItem({required this.createdAt, required this.track});

  final DateTime createdAt;
  final CatalogTrack track;

  factory FavoriteItem.fromJson(Map<String, dynamic> data) {
    final createdAt = DateTime.tryParse(data['createdAt']?.toString() ?? '');
    final track = data['track'];
    if (createdAt == null || track is! Map<String, dynamic>) {
      throw const ApiFailure('Respuesta de favoritos inválida.');
    }
    return FavoriteItem(
      createdAt: createdAt,
      track: CatalogTrack.fromJson(track),
    );
  }
}
