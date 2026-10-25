import 'package:flutter/material.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/domain/auth_repository.dart';

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({super.key, this.url, this.size = 56});
  final String? url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.music_note, size: size / 2)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => fallback,
              ),
      ),
    );
  }
}

class CatalogError extends StatelessWidget {
  const CatalogError({super.key, required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error is ApiFailure
                ? (error as ApiFailure).message
                : error is AuthFailure
                ? (error as AuthFailure).message
                : 'No se pudo cargar el catálogo.',
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: retry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}
