import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../application/rating_providers.dart';

class RatingPanel extends ConsumerWidget {
  const RatingPanel({super.key, required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = ref.watch(ratingProvider(trackId));
    final action = ref.watch(ratingActionsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: rating.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Row(
            children: [
              const Expanded(child: Text('No se pudo cargar la calificación.')),
              TextButton(
                onPressed: () => ref.invalidate(ratingProvider(trackId)),
                child: const Text('Reintentar'),
              ),
            ],
          ),
          data: (summary) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tu calificación',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var score = 1; score <= 5; score++)
                    IconButton(
                      tooltip: '$score de 5',
                      onPressed: action.isLoading
                          ? null
                          : () => _update(context, ref, score),
                      icon: Icon(
                        score <= (summary.myScore ?? 0)
                            ? Icons.star
                            : Icons.star_border,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  if (summary.myScore != null)
                    TextButton(
                      onPressed: action.isLoading
                          ? null
                          : () => _update(context, ref, null),
                      child: const Text('Quitar'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(_summaryText(summary.averageScore, summary.ratingCount)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _update(BuildContext context, WidgetRef ref, int? score) async {
    final messenger = ScaffoldMessenger.of(context);
    final updated = await ref
        .read(ratingActionsProvider.notifier)
        .set(trackId, score);
    if (!context.mounted) return;
    if (!updated) {
      final error = ref.read(ratingActionsProvider).error;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is ApiFailure
                ? error.message
                : 'No se pudo guardar la calificación.',
          ),
        ),
      );
    }
  }
}

String _summaryText(double? average, int count) {
  if (average == null || count == 0) return 'Aún no hay calificaciones.';
  final noun = count == 1 ? 'calificación' : 'calificaciones';
  return 'Promedio ${average.toStringAsFixed(1)} de 5 · $count $noun';
}
