// The locked just_audio version exposes byte-range streams through its experimental API.
// ignore_for_file: experimental_member_use

import 'package:just_audio/just_audio.dart';
import '../domain/track_audio_engine.dart';

class AccountAudioSource extends StreamAudioSource {
  AccountAudioSource(this.read);
  final TrackAudioReader read;
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final data = await read(start, end);
    return StreamAudioResponse(
      sourceLength: data.total,
      contentLength: data.length,
      offset: data.offset,
      contentType: data.contentType,
      stream: data.stream,
      rangeRequestsSupported: data.acceptsRanges,
    );
  }
}
