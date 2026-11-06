import '../../search/domain/catalog_track.dart';
import '../../../core/network/authenticated_api_client.dart';

enum PlaylistVisibility {
  private('private'),
  public('public');

  const PlaylistVisibility(this.apiValue);
  final String apiValue;
}

class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.visibility,
    required this.trackCount,
    required this.createdAt,
    required this.updatedAt,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
  final PlaylistVisibility visibility;
  final int trackCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PlaylistSummary.fromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final name = data['name'];
    final description = data['description'];
    final visibility = switch (data['visibility']) {
      'private' => PlaylistVisibility.private,
      'public' => PlaylistVisibility.public,
      _ => null,
    };
    final count = data['trackCount'];
    final created = DateTime.tryParse(data['createdAt']?.toString() ?? '');
    final updated = DateTime.tryParse(data['updatedAt']?.toString() ?? '');
    if (id is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(id) ||
        name is! String ||
        name.isEmpty ||
        name.length > 150 ||
        (description != null && description is! String) ||
        visibility == null ||
        count is! int ||
        count < 0 ||
        created == null ||
        updated == null) {
      throw const ApiFailure('Respuesta de playlists inválida.');
    }
    return PlaylistSummary(
      id: id,
      name: name,
      description: description as String?,
      visibility: visibility,
      trackCount: count,
      createdAt: created,
      updatedAt: updated,
    );
  }
}

class PlaylistItem {
  const PlaylistItem({
    required this.id,
    required this.position,
    required this.addedAt,
    required this.track,
  });
  final String id;
  final int position;
  final DateTime addedAt;
  final CatalogTrack track;

  factory PlaylistItem.fromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final position = data['position'];
    final addedAt = DateTime.tryParse(data['addedAt']?.toString() ?? '');
    final track = data['track'];
    if (id is! String ||
        position is! int ||
        position < 0 ||
        addedAt == null ||
        track is! Map<String, dynamic>) {
      throw const ApiFailure('Respuesta de playlist inválida.');
    }
    return PlaylistItem(
      id: id,
      position: position,
      addedAt: addedAt,
      track: CatalogTrack.fromJson(track),
    );
  }
}

class PlaylistDetail extends PlaylistSummary {
  const PlaylistDetail({
    required super.id,
    required super.name,
    required super.visibility,
    required super.trackCount,
    required super.createdAt,
    required super.updatedAt,
    required this.ownedByCurrentUser,
    required this.tracks,
    super.description,
  });

  final bool ownedByCurrentUser;
  final List<PlaylistItem> tracks;

  factory PlaylistDetail.fromJson(Map<String, dynamic> data) {
    final base = PlaylistSummary.fromJson(data);
    final owner = data['ownedByCurrentUser'];
    final tracks = data['tracks'];
    if (owner is! bool || tracks is! List || tracks.length > 500) {
      throw const ApiFailure('Respuesta de playlist inválida.');
    }
    final items = tracks
        .map((value) {
          if (value is! Map<String, dynamic>) {
            throw const ApiFailure('Respuesta de playlist inválida.');
          }
          return PlaylistItem.fromJson(value);
        })
        .toList(growable: false);
    for (var index = 0; index < items.length; index++) {
      if (items[index].position != index) {
        throw const ApiFailure('Orden de playlist inválido.');
      }
    }
    if (base.trackCount != items.length) {
      throw const ApiFailure('Respuesta de playlist inválida.');
    }
    return PlaylistDetail(
      id: base.id,
      name: base.name,
      description: base.description,
      visibility: base.visibility,
      trackCount: base.trackCount,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      ownedByCurrentUser: owner,
      tracks: items,
    );
  }
}
