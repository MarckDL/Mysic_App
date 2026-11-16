import 'dart:math' as math;
import 'dart:typed_data';

/// Extracts normalized RMS amplitudes from signed 16-bit PCM samples.
/// This helper consumes *actual decoded samples*, not metadata or placeholders.
/// It is independent of a codec: Android AAC/M4A still needs a PCM tap.
class PcmWaveformAnalyzer {
  const PcmWaveformAnalyzer();

  List<double> analyze(Int16List samples, {int bars = 100}) {
    if (bars <= 0) throw ArgumentError.value(bars, 'bars', 'Must be positive');
    if (samples.isEmpty) return const [];
    final result = List<double>.filled(bars, 0);
    var maximum = 0.0;
    for (var i = 0; i < bars; i++) {
      final start = i * samples.length ~/ bars;
      final end = math.min(samples.length, (i + 1) * samples.length ~/ bars);
      if (end <= start) continue;
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        final normalized = samples[j] / 32768.0;
        sum += normalized * normalized;
      }
      final rms = math.sqrt(sum / (end - start));
      result[i] = rms;
      maximum = math.max(maximum, rms);
    }
    if (maximum <= 0) return result;
    return result.map((value) => (value / maximum).clamp(0.0, 1.0)).toList();
  }
}
