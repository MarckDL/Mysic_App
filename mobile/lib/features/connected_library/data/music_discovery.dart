import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../domain/music_mode.dart';

enum MusicSearchFilter {
  all('Todo'),
  song('Canciones'),
  video('Vídeos'),
  artist('Artistas'),
  album('Álbumes');

  const MusicSearchFilter(this.label);
  final String label;
}

typedef DiscoveryRequest = ({
  String path,
  String? query,
  MusicSearchFilter? filter,
});

const exploreRequest = (path: 'explore', query: null, filter: null);

final discoveryPageProvider = FutureProvider.autoDispose
    .family<MusicPage, DiscoveryRequest>((ref, request) async {
      final api = AuthenticatedApiClient(
        ref.watch(authRepositoryProvider),
        baseUrl: ApiConfig.baseUrl,
      );
      final cancel = CancelToken();
      ref.onDispose(() {
        cancel.cancel();
        api.close();
      });
      final data = await api.get(
        '/api/v1/catalog/discovery/${request.path}',
        query: {
          if (request.query != null) 'q': request.query,
          if (request.filter != null) 'type': request.filter!.name,
        },
        cancelToken: cancel,
      );
      return MusicPage.fromJson(data);
    }, retry: (count, error) => null);
