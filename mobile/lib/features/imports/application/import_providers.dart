import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../data/import_client.dart';
import '../../playlists/application/playlist_providers.dart';
import 'import_controller.dart';
import '../data/takeout_file_picker.dart';

final importClientProvider = Provider.autoDispose<ImportClient>((ref) {
  final client = ImportClient(
    AuthenticatedApiClient(
      ref.watch(authRepositoryProvider),
      baseUrl: ApiConfig.baseUrl,
      keepSessionOnForbidden: true,
    ),
  );
  ref.onDispose(client.close);
  return client;
});

final takeoutFilePickerProvider = Provider<TakeoutFilePicker>(
  (ref) => TakeoutFilePicker(),
);

final importControllerProvider = Provider.autoDispose<ImportController>((ref) {
  ref.watch(authStateProvider.select((value) => value.asData?.value?.uid));
  final controller = ImportController(
    ref.watch(importClientProvider),
    ref.watch(takeoutFilePickerProvider),
    onSaved: () => ref.invalidate(playlistsProvider),
  );
  ref.onDispose(controller.dispose);
  controller.load();
  return controller;
});
