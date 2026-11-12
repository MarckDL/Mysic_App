import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../application/favorite_providers.dart';

class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(favoriteStatusProvider(trackId));
    final action = ref.watch(favoriteActionsProvider);
    return status.when(
      loading: () => const IconButton(
        tooltip: 'Cargando favorito',
        onPressed: null,
        icon: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (error, stack) => IconButton(
        tooltip: 'Reintentar favorito',
        onPressed: () => ref.invalidate(favoriteStatusProvider(trackId)),
        icon: const Icon(Icons.favorite_border),
      ),
      data: (isFavorite) => IconButton.filledTonal(
        tooltip: isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
        onPressed: action.isLoading
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                final updated = await ref
                    .read(favoriteActionsProvider.notifier)
                    .set(trackId, !isFavorite);
                if (!context.mounted) return;
                if (updated) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        isFavorite
                            ? 'Canción eliminada de favoritos'
                            : 'Canción añadida a favoritos',
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                } else {
                  final error = ref.read(favoriteActionsProvider).error;
                  messenger.showSnackBar(
                    SnackBar(content: Text(_favoriteErrorText(error))),
                  );
                }
              },
        icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
      ),
    );
  }
}

String _favoriteErrorText(Object? error) => error is ApiFailure
    ? error.message
    : 'No se pudo actualizar el favorito. Inténtalo de nuevo.';
