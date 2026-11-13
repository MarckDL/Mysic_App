import '../../../core/network/authenticated_api_client.dart';

class TrackInteractions {
  const TrackInteractions({
    required this.isFavorite,
    required this.myRating,
    required this.ratingAverage,
    required this.ratingCount,
  });

  final bool isFavorite;
  final int? myRating;
  final double? ratingAverage;
  final int ratingCount;

  factory TrackInteractions.fromJson(Map<String, dynamic> data) {
    final favorite = data['isFavorite'];
    final mine = data['myRating'];
    final average = data['ratingAverage'];
    final count = data['ratingCount'];
    if (favorite is! bool ||
        (mine != null && (mine is! int || mine < 1 || mine > 5)) ||
        (average != null && (average is! num || average < 1 || average > 5)) ||
        count is! int ||
        count < 0 ||
        (count == 0 && average != null) ||
        (count > 0 && average == null)) {
      throw const ApiFailure('Respuesta de calificaciones inválida.');
    }
    return TrackInteractions(
      isFavorite: favorite,
      myRating: mine as int?,
      ratingAverage: (average as num?)?.toDouble(),
      ratingCount: count,
    );
  }

  TrackInteractions withRating(Map<String, dynamic> data) =>
      TrackInteractions.fromJson({...data, 'isFavorite': isFavorite});
}
