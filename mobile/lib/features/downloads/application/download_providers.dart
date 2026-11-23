import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../playback/domain/playback_source_resolver.dart';
import '../data/download_store.dart';

/// Cómo se pide la URL de un audio al resolvedor del teléfono para
/// descargarlo. Tiene su propio canal de resolución: no comparte estado con el
/// del reproductor, y vive lo que la app (cerrarlo vaciaría las cachés
/// nativas de resolución).
final downloadResolverProvider = Provider<DownloadSourceResolver>((ref) {
  final resolver = createPlaybackSourceResolver();
  return (sourceId, {refresh = false}) =>
      resolver.resolve(sourceId, 'device', refresh: refresh);
});
