import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../../search/domain/catalog_track.dart';

typedef ListeningEntry = ({CatalogTrack track, DateTime startedAt});
typedef HistoryPage = ({List<ListeningEntry> items, String? nextCursor});

class HistoryClient {
  const HistoryClient(this._api);

  final AuthenticatedApiClient _api;

  Future<List<ListeningEntry>> recentDistinct() async {
    final recent = <String, ListeningEntry>{};
    String? cursor;
    do {
      final page = await list(limit: 50, cursor: cursor);
      for (final entry in page.items) {
        recent.putIfAbsent(entry.track.id, () => entry);
        if (recent.length == 5) return recent.values.toList(growable: false);
      }
      cursor = page.nextCursor;
    } while (cursor != null);
    return recent.values.toList(growable: false);
  }

  Future<HistoryPage> list({required int limit, String? cursor}) async {
    final data = await _api.get(
      '/api/v1/history',
      query: {'limit': limit, if (cursor != null) 'cursor': cursor},
    );
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    return (
      items: [
        for (final item in items)
          (
            track: CatalogTrack.fromJson(item['track'] as Map<String, dynamic>),
            startedAt: DateTime.parse(item['startedAt'] as String).toLocal(),
          ),
      ],
      nextCursor: data['nextCursor'] as String?,
    );
  }
}

final historyClientProvider = Provider.autoDispose<HistoryClient>((ref) {
  final user = ref.watch(authStateProvider).asData?.value;
  if (user == null) throw const AuthFailure('Inicia sesión con Google.');
  final api = AuthenticatedApiClient(
    ref.watch(authRepositoryProvider),
    baseUrl: ApiConfig.baseUrl,
  );
  ref.onDispose(api.close);
  return HistoryClient(api);
});

final recentListeningProvider = FutureProvider.autoDispose
    .family<List<ListeningEntry>, String>((ref, uid) async {
      return ref.watch(historyClientProvider).recentDistinct();
    }, retry: (count, error) => null);
