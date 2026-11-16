import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/playback/domain/pcm_waveform_analyzer.dart';

void main() {
  const analyzer = PcmWaveformAnalyzer();
  test('silence generates zero energy', () {
    expect(analyzer.analyze(Int16List(40), bars: 4), [0, 0, 0, 0]);
  });
  test('actual PCM amplitude is reflected in measured peaks', () {
    final values = Int16List.fromList([
      0,
      0,
      0,
      0,
      8192,
      -8192,
      8192,
      -8192,
      32767,
      -32768,
      32767,
      -32768,
    ]);
    final peaks = analyzer.analyze(values, bars: 3);
    expect(peaks[0], 0);
    expect(peaks[1], greaterThan(0));
    expect(peaks[2], closeTo(1, 0.0001));
  });
  test('reject invalid bar counts', () {
    expect(() => analyzer.analyze(Int16List(4), bars: 0), throwsArgumentError);
  });
}
