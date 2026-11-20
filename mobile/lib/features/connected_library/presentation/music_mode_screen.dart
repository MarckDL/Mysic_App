import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/presentation/account_screen.dart'
    show AccountAction;
import '../../playback/application/playback_providers.dart';
import '../../search/presentation/catalog_widgets.dart' show TrackArtwork;
import '../application/connected_host.dart';
import '../application/music_mode_controller.dart';
import '../domain/music_mode.dart';
import 'music_mode_host.dart';

class MusicModeSurface extends StatelessWidget {
  const MusicModeSurface({
    super.key,
    required this.surface,
    this.local,
    this.playlistId,
  });

  final MusicSurface surface;
  final Widget? local;
  final String? playlistId;

  @override
  Widget build(BuildContext context) {
    final controller = MusicModeScope.of(context);
    if (local != null && controller?.showMusic != true) return local!;
    final connection = controller?.connection;
    if (controller == null ||
        controller.transitioning ||
        connection?.status != MusicLinkStatus.linked ||
        !controller.wantsMusic) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('YouTube Music'),
          actions: const [AccountAction()],
        ),
        body: Center(
          child: controller?.busy == true
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      connection?.serverPending == true
                          ? 'El servidor de Mysic aún no ofrece la biblioteca musical de tu cuenta.'
                          : controller?.failed == true
                          ? 'No se pudo comprobar la conexión.'
                          : 'Selecciona una cuenta en las opciones de conexión.',
                    ),
                    if (controller?.failed == true ||
                        connection?.serverPending == true)
                      TextButton(
                        onPressed: () => unawaited(controller!.refresh()),
                        child: const Text('Reintentar'),
                      ),
                    if (connection?.serverPending == true)
                      TextButton(
                        onPressed: controller!.useLocal,
                        child: const Text('Usar mi biblioteca de Mysic'),
                      ),
                    TextButton(
                      onPressed: () => context.push('/account'),
                      child: const Text('Opciones de conexión'),
                    ),
                  ],
                ),
        ),
      );
    }
    return _MusicPage(
      key: ValueKey((
        connection!.generation,
        controller.revision,
        surface,
        playlistId,
      )),
      controller: controller,
      connection: connection,
      surface: surface,
      playlistId: playlistId,
    );
  }
}

class MusicModeSettings extends StatelessWidget {
  const MusicModeSettings({super.key});

  Future<void> _select(
    BuildContext context,
    MusicModeController controller,
  ) async {
    final selected = await showDialog<MusicAccount>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Confirma la cuenta musical'),
        children: [
          for (final account in controller.connection!.accounts)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(account),
              child: Text(account.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (selected != null && context.mounted) await controller.select(selected);
  }

  Future<void> _activity(
    BuildContext context,
    MusicModeController controller,
    String generation, {
    bool? paused,
  }) async {
    if (paused == null) {
      final clear = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Borrar la actividad de Mysic?'),
          content: const Text(
            'Se borrarán Recientes en Mysic y En repetición de este vínculo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar'),
            ),
          ],
        ),
      );
      if (clear != true || !context.mounted) return;
    }
    try {
      await controller.updateActivity(generation, paused: paused);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el cambio.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = MusicModeScope.of(context);
    if (controller == null) return const SizedBox.shrink();
    final connection = controller.connection;
    if (connection?.serverPending == true) {
      return ListTile(
        title: const Text('YouTube Music'),
        subtitle: const Text(
          'El servidor aún no ofrece la biblioteca musical de tu cuenta.',
        ),
        trailing: TextButton(
          onPressed: controller.busy ? null : controller.refresh,
          child: const Text('Reintentar'),
        ),
      );
    }
    if (connection?.status == MusicLinkStatus.unavailable &&
        ConnectedScope.of(context) != null) {
      return const SizedBox.shrink();
    }
    final account = connection?.account;
    final managesAccount =
        connection?.status == MusicLinkStatus.linked ||
        (connection?.status == MusicLinkStatus.unavailable &&
            connection?.generation != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.headphones),
          title: Text(
            connection?.isPreview == true
                ? 'YouTube Music · simulación'
                : 'YouTube Music',
          ),
          subtitle: Text(switch (connection?.status) {
            MusicLinkStatus.linked when controller.wantsMusic =>
              'Modo activo · ${account!.name}',
            MusicLinkStatus.expired => 'Sesión caducada · ${account!.name}',
            MusicLinkStatus.unavailable => 'Conexión musical no disponible',
            MusicLinkStatus.unlinked ||
            MusicLinkStatus.linked => 'Modo activo · Mysic',
            null =>
              controller.failed
                  ? 'Conexión sin verificar'
                  : 'Comprobando conexión…',
          }),
          trailing: controller.busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        if (controller.failed)
          ListTile(
            title: const Text('Revisar conexión'),
            subtitle: Text(switch (controller.failureCode) {
              'TOO_MANY_REQUESTS' => 'Espera antes de volver a iniciar sesión.',
              _ => 'Intenta nuevamente.',
            }),
            onTap: controller.busy
                ? null
                : () => unawaited(controller.refresh()),
          ),
        if (connection?.isDirect == true &&
            (connection?.status != MusicLinkStatus.unavailable ||
                managesAccount) &&
            ConnectedScope.of(context) != null) ...[
          if (connection!.status == MusicLinkStatus.linked &&
              !controller.wantsMusic)
            ListTile(
              leading: const Icon(Icons.library_music),
              title: const Text('Usar el canal vinculado'),
              onTap: controller.useLinkedAccount,
            ),
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(
              managesAccount
                  ? 'Gestionar cuenta vinculada'
                  : 'Vincular YouTube Music',
            ),
            subtitle: const Text('Con tu cuenta de Google'),
            onTap: () {
              final link = ConnectedScope.of(context)!;
              context.push('/library/youtube');
              if (!link.busy && link.pending == null && !managesAccount) {
                unawaited(link.start());
              }
            },
          ),
        ],
        if (connection?.accounts.isNotEmpty == true)
          ListTile(
            title: Text(switch (connection!.status) {
              MusicLinkStatus.linked when controller.wantsMusic =>
                'Cambiar cuenta o canal',
              MusicLinkStatus.expired => 'Reconectar YouTube Music',
              _ => 'Activar YouTube Music',
            }),
            onTap: controller.busy
                ? null
                : () => unawaited(_select(context, controller)),
          ),
        if (controller.wantsMusic &&
            connection?.isDirect == true &&
            connection!.capabilities.contains('recordInMysic') &&
            connection.generation != null) ...[
          SwitchListTile(
            title: const Text('Registrar escuchas en Mysic'),
            subtitle: const Text('Para Recientes en Mysic y En repetición'),
            value: connection.account?.historyPaused != true,
            onChanged: controller.updatingActivity
                ? null
                : (value) => _activity(
                    context,
                    controller,
                    connection.generation!,
                    paused: !value,
                  ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Borrar actividad de Mysic'),
            onTap: controller.updatingActivity
                ? null
                : () => _activity(context, controller, connection.generation!),
          ),
        ],
        if (controller.wantsMusic && connection?.isDirect == true)
          ListTile(
            title: const Text('Usar mi biblioteca de Mysic'),
            onTap: controller.useLocal,
          ),
        if (connection?.isDirect != true &&
            (controller.wantsMusic || connection?.generation != null))
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text('Desvincular y volver a Mysic'),
            onTap: controller.busy
                ? null
                : () => unawaited(controller.returnToMysic()),
          ),
        if (controller.failed)
          ListTile(
            title: const Text('Usar Mysic en este dispositivo'),
            onTap: controller.busy ? null : controller.useLocal,
          ),
      ],
    );
  }
}

class _MusicPage extends ConsumerStatefulWidget {
  const _MusicPage({
    super.key,
    required this.controller,
    required this.connection,
    required this.surface,
    this.playlistId,
  });

  final MusicModeController controller;
  final MusicConnection connection;
  final MusicSurface surface;
  final String? playlistId;

  @override
  ConsumerState<_MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends ConsumerState<_MusicPage> {
  final _items = <MusicItem>[];
  final _search = TextEditingController();
  CancelToken? _request;
  String? _cursor;
  String? _query;
  String? _playlistTitle;
  String? _error;
  bool _loading = false;
  int _excluded = 0;
  late MusicSurface _surface =
      (widget.surface == MusicSurface.songs ||
              (widget.surface == MusicSurface.home &&
                  !widget.connection.capabilities.contains('home'))) &&
          widget.connection.isDirect
      ? MusicSurface.playlists
      : widget.surface == MusicSurface.history &&
            widget.connection.isDirect &&
            widget.connection.capabilities.contains('mysicRecents')
      ? MusicSurface.mysicRecents
      : widget.surface;

  @override
  void initState() {
    super.initState();
    if (_surface != MusicSurface.search) unawaited(_load(reset: true));
  }

  Future<void> _load({required bool reset, String? query}) async {
    final generation = widget.connection.generation!;
    if (!widget.connection.capabilities.contains(_surface.name) ||
        !widget.controller.isCurrent(generation) ||
        (_loading && !reset)) {
      return;
    }
    if (_surface == MusicSurface.search && (query ?? _query ?? '').isEmpty) {
      return;
    }
    _request?.cancel();
    final request = _request = CancelToken();
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _cursor = null;
        _excluded = 0;
        if (query != null) _query = query;
      }
    });
    try {
      final page = await widget.controller.page(
        generation,
        _surface,
        playlistId: widget.playlistId,
        query: _query,
        cursor: _cursor,
        cancelToken: request,
      );
      if (!mounted ||
          request != _request ||
          !widget.controller.isCurrent(generation)) {
        return;
      }
      setState(() {
        _cursor = page.nextCursor;
        _items.addAll(page.items);
        _playlistTitle = page.title ?? page.playlist?.title ?? _playlistTitle;
        _excluded += page.excludedCount;
      });
    } on ApiFailure catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = switch (error.code) {
            'INVALID_CURSOR' ||
            'CURSOR_EXPIRED' => 'La página caducó. Actualiza la lista.',
            'MUSIC_ACCESS_DENIED' =>
              'YouTube Music no autorizó la lectura de esta cuenta.',
            'MUSIC_CATALOG_RESPONSE' =>
              'YouTube Music devolvió un formato que Mysic no puede leer.',
            'MUSIC_PLAYLIST_NOT_FOUND' =>
              'La playlist ya no está disponible en esta cuenta.',
            _ => 'No se pudo cargar. Inténtalo de nuevo.',
          };
        });
      }
    } catch (_) {
      if (mounted && request == _request && !request.isCancelled) {
        setState(() => _error = 'No se pudo cargar. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _searchFor(String value) {
    final query = value.trim();
    if (query.isEmpty) {
      _request?.cancel();
      _request = null;
      setState(() {
        _items.clear();
        _loading = false;
        _error = null;
        _cursor = null;
        _query = null;
      });
      return;
    }
    unawaited(_load(reset: true, query: query));
  }

  bool _canPlayTrack(MusicTrack track) => widget.connection.isPreview
      ? widget.connection.capabilities.contains('playback') && track.canPreview
      : (widget.controller.deviceAudio(track.id) != null ||
            (widget.connection.capabilities.contains('playback') &&
                track.canPlayInMysic));

  Future<void> _trackAction(String action, MusicItem item) async {
    final generation = widget.connection.generation!;
    final model = widget.controller;
    if (!model.isCurrent(generation)) return;
    String? message;
    try {
      if (action == 'share') {
        final uri = switch (item) {
          MusicPlaylist() => Uri.https('music.youtube.com', '/playlist', {
            'list': item.id,
          }),
          MusicAlbum() => Uri.https('music.youtube.com', '/browse/${item.id}'),
          MusicArtist() => Uri.https('music.youtube.com', '/browse/${item.id}'),
          MusicTrack() => Uri.https('music.youtube.com', '/watch', {
            'v': item.id,
          }),
        };
        await Clipboard.setData(ClipboardData(text: uri.toString()));
        message = 'Enlace copiado';
      } else if (item is MusicTrack) {
        if (action == 'file') {
          if (await model.attachAudio(generation, item.id)) {
            message = 'Archivo listo para reproducir en Mysic';
          }
        } else if (action == 'remove') {
          await model.removeAudio(generation, item.id);
          message = 'Archivo retirado de Mysic';
        } else if (action == 'artist' && item.artistId != null) {
          context.push('/music/artist/${item.artistId}');
        } else if ((action == 'next' || action == 'last') &&
            _canPlayTrack(item)) {
          message = _addToQueue([item], next: action == 'next');
        }
      }
    } on Object {
      message = action == 'file'
          ? 'No se pudo leer el archivo de audio.'
          : 'No se pudo completar la acción.';
    }
    if (mounted && message != null && model.isCurrent(generation)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _addToQueue(Iterable<MusicTrack> tracks, {required bool next}) {
    final music = widget.controller;
    final generation = widget.connection.generation!;
    if (!music.isCurrent(generation)) return 'Cambió la conexión.';
    final added = ref
        .read(trackPlaybackControllerProvider)
        .queueConnected(
          tracks
              .where(_canPlayTrack)
              .map(
                (track) => track.toPlaybackTrack(
                  deviceAudio: music.deviceAudio(track.id),
                ),
              ),
          next: next,
          listenForTrack: () => music.listenForTrack(generation),
        );
    if (!added) return 'La cola no cambió';
    return next
        ? 'Se reproducirá a continuación'
        : 'Añadido al final de la cola';
  }

  Widget _actions(MusicItem item) {
    final track = item is MusicTrack ? item : null;
    final file =
        track != null && widget.controller.deviceAudio(track.id) != null;
    return PopupMenuButton<String>(
      tooltip: 'Opciones de ${item.title}',
      onSelected: (action) => unawaited(_trackAction(action, item)),
      itemBuilder: (context) => [
        if (track != null && _canPlayTrack(track)) ...[
          const PopupMenuItem(
            value: 'next',
            child: Text('Reproducir a continuación'),
          ),
          const PopupMenuItem(
            value: 'last',
            child: Text('Añadir al final de la cola'),
          ),
        ],
        if (track?.artistId != null &&
            widget.connection.capabilities.contains('artist'))
          const PopupMenuItem(
            value: 'artist',
            child: Text('Más de este canal'),
          ),
        if (track != null && widget.controller.device != null)
          PopupMenuItem(
            value: 'file',
            enabled: !widget.controller.pickingAudio,
            child: Text(
              file ? 'Cambiar archivo de audio' : 'Vincular archivo de audio',
            ),
          ),
        if (file)
          PopupMenuItem(
            value: 'remove',
            enabled: !widget.controller.pickingAudio,
            child: const Text('Retirar archivo de Mysic'),
          ),
        const PopupMenuItem(value: 'share', child: Text('Copiar enlace')),
      ],
    );
  }

  void _play(MusicTrack selected, {bool shuffled = false}) {
    final generation = widget.connection.generation!;
    if (!widget.controller.isCurrent(generation)) return;
    final tracks = _items.whereType<MusicTrack>().where(_canPlayTrack).toList();
    final selectedIndex = tracks.indexOf(selected);
    if (selectedIndex < 0) return;
    final start = selectedIndex ~/ 100 * 100;
    final queue = tracks
        .skip(start)
        .take(100)
        .map(
          (item) => item.toPlaybackTrack(
            deviceAudio: widget.controller.deviceAudio(item.id),
          ),
        )
        .toList();
    final music = widget.controller;
    final controller = ref.read(trackPlaybackControllerProvider);
    unawaited(
      controller.playQueue(
        queue,
        initialIndex: selectedIndex - start,
        shuffled: shuffled,
        listenForTrack: widget.connection.isDirect
            ? () => music.listenForTrack(generation)
            : null,
        onPreviewListened: widget.connection.isPreview
            ? (id, trackId, ms) => music.onListened(generation, id, trackId, ms)
            : null,
      ),
    );
    context.push('/player');
  }

  String get _title => switch (widget.surface) {
    MusicSurface.home => 'Inicio',
    MusicSurface.songs => 'Biblioteca',
    MusicSurface.liked => 'Me gusta de YouTube Music',
    MusicSurface.albums => 'Álbumes',
    MusicSurface.album => _playlistTitle ?? 'Álbum',
    MusicSurface.playlist => _playlistTitle ?? 'Playlist',
    MusicSurface.search => 'Buscar',
    MusicSurface.history =>
      widget.connection.isDirect ? 'Recientes en Mysic' : 'Recientes',
    MusicSurface.mysicRecents => 'Recientes en Mysic',
    MusicSurface.onRepeat => 'En repetición',
    MusicSurface.artist => 'Más de este canal',
    MusicSurface.artists => 'Canales musicales que sigues',
    MusicSurface.playlists => 'Biblioteca',
  };

  @override
  Widget build(BuildContext context) {
    final account = widget.connection.account!;
    final firstPlayable = _items
        .whereType<MusicTrack>()
        .where(_canPlayTrack)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if ((widget.connection.capabilities.contains('history') ||
                  widget.connection.capabilities.contains('mysicRecents')) &&
              (widget.surface == MusicSurface.home ||
                  widget.surface == MusicSurface.songs))
            IconButton(
              tooltip: 'Abrir Recientes',
              icon: const Icon(Icons.history),
              onPressed: () => context.push('/history'),
            ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => unawaited(_load(reset: true)),
          ),
          if (widget.surface != MusicSurface.playlist &&
              widget.surface != MusicSurface.history)
            const AccountAction(),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: [
            Text(
              widget.connection.isPreview
                  ? 'Simulación de YouTube Music · ${account.name}'
                  : 'YouTube Music · ${account.name}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (widget.surface == MusicSurface.home &&
                widget.connection.capabilities.contains('onRepeat'))
              ListTile(
                leading: const Icon(Icons.repeat),
                title: const Text('En repetición'),
                subtitle: const Text(
                  'Tus canciones más escuchadas en Mysic en los últimos 30 días',
                ),
                onTap: () => context.push('/music/repeat'),
              ),
            if (widget.surface == MusicSurface.home)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.connection.capabilities.contains('home')
                      ? 'Recomendaciones de YouTube Music'
                      : 'Tus playlists musicales',
                ),
              ),
            if (widget.surface == MusicSurface.songs &&
                widget.connection.capabilities.contains('artists'))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.people_outline),
                title: const Text('Canales musicales que sigues'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/music/artists'),
              ),
            if (widget.surface == MusicSurface.songs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final section in {
                      if (widget.connection.capabilities.contains('songs'))
                        MusicSurface.songs: 'Canciones',
                      if (widget.connection.capabilities.contains('liked'))
                        MusicSurface.liked: widget.connection.isDirect
                            ? 'Me gusta de YouTube Music'
                            : 'Me gusta',
                      MusicSurface.playlists: 'Playlists',
                      if (widget.connection.capabilities.contains('albums'))
                        MusicSurface.albums: 'Álbumes',
                    }.entries)
                      ChoiceChip(
                        label: Text(section.value),
                        selected: _surface == section.key,
                        onSelected: (_) {
                          if (_surface == section.key) return;
                          setState(() => _surface = section.key);
                          unawaited(_load(reset: true));
                        },
                      ),
                  ],
                ),
              ),
            if (_surface == MusicSurface.songs && widget.connection.isDirect)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Canciones de tu biblioteca musical'),
              ),
            if (widget.connection.isDirect &&
                firstPlayable != null &&
                const {
                  MusicSurface.songs,
                  MusicSurface.liked,
                  MusicSurface.playlist,
                  MusicSurface.album,
                  MusicSurface.artist,
                  MusicSurface.onRepeat,
                }.contains(_surface))
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Reproducir'),
                    onPressed: () => _play(firstPlayable),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Aleatorio'),
                    onPressed: () => _play(firstPlayable, shuffled: true),
                  ),
                  PopupMenuButton<bool>(
                    tooltip: 'Opciones de cola',
                    icon: const Icon(Icons.playlist_add),
                    onSelected: (next) {
                      final message = _addToQueue(
                        _items.whereType<MusicTrack>(),
                        next: next,
                      );
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: true,
                        child: Text(
                          'Reproducir estas canciones a continuación',
                        ),
                      ),
                      PopupMenuItem(
                        value: false,
                        child: Text(
                          'Añadir estas canciones al final de la cola',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            if (_surface == MusicSurface.search)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: TextField(
                  controller: _search,
                  maxLength: 120,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: widget.connection.isDirect
                        ? 'Buscar grabaciones en YouTube'
                        : 'Buscar en YouTube Music',
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: 'Buscar',
                      icon: const Icon(Icons.search),
                      onPressed: () => _searchFor(_search.text),
                    ),
                  ),
                  onSubmitted: _searchFor,
                ),
              ),
            if ((_surface == MusicSurface.history ||
                    _surface == MusicSurface.mysicRecents ||
                    _surface == MusicSurface.onRepeat) &&
                account.historyPaused)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('El historial está pausado.'),
              ),
            if (_excluded > 0)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Elementos omitidos: $_excluded'),
                subtitle: const Text(
                  'Incluye videos ajenos a la biblioteca musical y pistas no disponibles.',
                ),
              ),
            for (final item in _items)
              switch (item) {
                MusicAlbum() => ListTile(
                  leading: TrackArtwork(
                    url: item.thumbnailUrl,
                    size: 44,
                    fallbackIcon: Icons.album,
                  ),
                  title: Text(item.title),
                  subtitle: const Text('Álbum'),
                  onTap: () => context.push(
                    '/music/album/${Uri.encodeComponent(item.id)}',
                  ),
                ),
                MusicArtist() => ListTile(
                  leading: TrackArtwork(
                    url: item.thumbnailUrl,
                    size: 44,
                    borderRadius: 22,
                    fallbackIcon: Icons.person_outline,
                  ),
                  title: Text(item.title),
                  trailing: _actions(item),
                  onTap: () => context.push(
                    '/music/artist/${Uri.encodeComponent(item.id)}',
                  ),
                ),
                MusicPlaylist() => ListTile(
                  leading: TrackArtwork(
                    url: item.thumbnailUrl,
                    size: 44,
                    fallbackIcon: Icons.queue_music,
                  ),
                  title: Text(item.title),
                  subtitle: item.isPrivate ? const Text('Privada') : null,
                  trailing: widget.connection.isDirect
                      ? _actions(item)
                      : const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    '/music/playlist/${Uri.encodeComponent(item.id)}',
                  ),
                ),
                MusicTrack() => ListTile(
                  leading: TrackArtwork(
                    url: item.thumbnailUrl,
                    size: 44,
                    fallbackIcon: _canPlayTrack(item)
                        ? Icons.play_circle_outline
                        : Icons.music_note,
                  ),
                  title: Text(item.title),
                  trailing: widget.connection.isDirect ? _actions(item) : null,
                  subtitle: Text(
                    [
                      item.artist,
                      if (item.playCount != null) '${item.playCount} escuchas',
                      if (item.listenedAt != null && item.playCount == null)
                        MaterialLocalizations.of(
                          context,
                        ).formatShortDate(item.listenedAt!.toLocal()),
                      if (widget.connection.isDirect &&
                          widget.controller.deviceAudio(item.id) != null)
                        'En este dispositivo'
                      else if (widget.connection.isDirect &&
                          !_canPlayTrack(item))
                        'Solo biblioteca',
                    ].join(' · '),
                  ),
                  onTap: _canPlayTrack(item) ? () => _play(item) : null,
                ),
              },
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_error != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_error!),
                trailing: TextButton(
                  onPressed: () => unawaited(_load(reset: true)),
                  child: const Text('Reintentar'),
                ),
              ),
            if (!_loading && _error == null && _items.isEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  !widget.connection.capabilities.contains(_surface.name)
                      ? 'Esta función no está habilitada para la cuenta.'
                      : _surface == MusicSurface.search && _query == null
                      ? (widget.connection.isDirect
                            ? 'Busca por canción o artista.'
                            : 'Busca canciones y playlists.')
                      : _cursor != null
                      ? 'Hay más resultados por revisar.'
                      : _surface == MusicSurface.onRepeat
                      ? 'Aquí aparecerán las canciones que escuches al menos dos veces en Mysic.'
                      : _surface == MusicSurface.history ||
                            _surface == MusicSurface.mysicRecents
                      ? 'Aún no hay escuchas.'
                      : 'No hay resultados.',
                ),
              ),
            if (_cursor != null && !_loading && _error == null)
              TextButton(
                onPressed: () => unawaited(_load(reset: false)),
                child: const Text('Cargar más'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _request?.cancel();
    _search.dispose();
    super.dispose();
  }
}
