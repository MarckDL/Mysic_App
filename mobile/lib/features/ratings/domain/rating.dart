import '../../../core/network/authenticated_api_client.dart';

class RatingSummary {
  const RatingSummary({
    required this.myScore,
    required this.averageScore,
    required this.ratingCount,
  });

  final int? myScore;
  final double? averageScore;
  final int ratingCount;

  factory RatingSummary.fromJson(Map<String, dynamic> data) {
    final own = data['myScore'];
    final average = data['averageScore'];
    final count = data['ratingCount'];
    if ((own != null && (own is! int || own < 1 || own > 5)) ||
        (average != null && (average is! num || average < 1 || average > 5)) ||
        count is! int ||
        count < 0) {
      throw const ApiFailure('Respuesta de calificaciones inválida.');
    }
    return RatingSummary(
      myScore: own as int?,
      averageScore: (average as num?)?.toDouble(),
      ratingCount: count,
    );
  }
}
