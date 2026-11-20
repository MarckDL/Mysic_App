import '../../../core/network/authenticated_api_client.dart';

class CatalogTrack {
  const CatalogTrack({
    required this.id,
    required this.title,
    required this.artistName,
    this.durationSeconds,
    this.thumbnailUrl,
    this.licensedAudio,
    this.deviceAudio,
    this.musicAccountTrack = false,
  });
  static const musicPreviewPrefix = 'music-preview:';

  final String id;
  bool get isMusicPreview => id.startsWith(musicPreviewPrefix);
  final String title;
  final String artistName;
  final int? durationSeconds;
  final String? thumbnailUrl;
  final Uri? licensedAudio;
  final Uri? deviceAudio;
  final bool musicAccountTrack;
  bool get isConnectedAudio =>
      musicAccountTrack || deviceAudio != null || licensedAudio != null;

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
