import 'package:flutter/material.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/domain/auth_repository.dart';
import '../domain/catalog_track.dart';

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    super.key,
    this.url,
    this.size = 56,
    this.borderRadius = 8,
    this.fallbackIcon = Icons.music_note,
  });
  final String? url;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;
  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(fallbackIcon, size: size / 2)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
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

class TrackHeading extends StatelessWidget {
  const TrackHeading({super.key, required this.track});

  final CatalogTrack track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        TrackArtwork(url: track.thumbnailUrl, size: 184),
        const SizedBox(height: 16),
        Text(
          track.title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          track.artistName,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
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
