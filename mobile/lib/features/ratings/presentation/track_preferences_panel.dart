import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../favorites/application/favorite_providers.dart';
import '../application/rating_providers.dart';

class TrackPreferencesPanel extends ConsumerWidget {
  const TrackPreferencesPanel({super.key, required this.trackId});
  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interactions = ref.watch(trackInteractionsProvider(trackId));
    final favoriteAction = ref.watch(favoriteActionsProvider);
    final ratingAction = ref.watch(ratingActionsProvider);
    final mutating = favoriteAction.isLoading || ratingAction.isLoading;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: interactions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Row(
            children: [
              const Expanded(
                child: Text('No se pudieron cargar tus preferencias.'),
              ),
              TextButton(
                onPressed: () =>
                    ref.invalidate(trackInteractionsProvider(trackId)),
                child: const Text('Reintentar'),
              ),
            ],
          ),
          data: (value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value.isFavorite
                          ? 'Guardada en tus favoritos'
                          : 'Agregar a tus favoritos',
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: value.isFavorite
                        ? 'Quitar de favoritos'
                        : 'Agregar a favoritos',
                    onPressed: mutating
                        ? null
                        : () async {
                            final updated = await ref
                                .read(favoriteActionsProvider.notifier)
                                .setFavorite(trackId, !value.isFavorite);
                            if (!updated && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'No se pudieron actualizar tus favoritos.',
                                  ),
                                ),
                              );
                            }
                          },
                    icon: Icon(
                      value.isFavorite ? Icons.favorite : Icons.favorite_border,
                    ),
                  ),
                ],
              ),
              const Divider(),
              const Text('Tu calificación'),
              Row(
                children: List.generate(5, (index) {
                  final score = index + 1;
                  return IconButton(
                    tooltip: '$score ${score == 1 ? 'estrella' : 'estrellas'}',
                    visualDensity: VisualDensity.compact,
                    onPressed: mutating
                        ? null
                        : () async {
                            final updated = await ref
                                .read(ratingActionsProvider.notifier)
                                .rate(trackId, score, value.isFavorite);
                            if (!updated && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'No se pudo guardar tu calificación.',
                                  ),
                                ),
                              );
                            }
                          },
                    icon: Icon(
                      score <= (value.myRating ?? 0)
                          ? Icons.star
                          : Icons.star_border,
                    ),
                  );
                }),
              ),
              Text(
                value.ratingCount == 0
                    ? 'Aún no hay calificaciones.'
                    : '${value.ratingAverage!.toStringAsFixed(1)} de 5 · '
                          '${value.ratingCount} ${value.ratingCount == 1 ? 'voto' : 'votos'}',
              ),
              if (favoriteAction.hasError || ratingAction.hasError) ...[
                const SizedBox(height: 8),
                Text(
                  'La última actualización no se pudo completar.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
