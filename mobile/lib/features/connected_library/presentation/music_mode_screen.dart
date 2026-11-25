import 'dart:async';
import 'dart:math' show Random;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/images/cover_color.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent, ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../authentication/presentation/account_screen.dart'
    show AccountAction;
import '../../playback/application/playback_providers.dart';
import '../../playback/application/track_playback_controller.dart';
import '../../playback/domain/track_audio_engine.dart' show TrackAudioPhase;
import '../../search/presentation/catalog_widgets.dart' show TrackArtwork;
import '../../search/presentation/item_sheet.dart';
import '../../search/presentation/music_tiles.dart';
import '../application/music_mode_controller.dart';
import '../domain/music_mode.dart';
import '../domain/shortcut.dart';
import 'catalog_pages.dart';
import 'collection_actions.dart';
import 'home_sheets.dart';
import 'library_screen.dart';
import 'tab_top_bar.dart';
import 'music_mode_host.dart';
import 'search_screen.dart';
import 'track_sheet.dart';

class MusicModeSurface extends StatelessWidget {
  const MusicModeSurface({
    super.key,
    required this.surface,
    this.playlistId,
    this.seed,
  });

  final MusicSurface surface;
  final String? playlistId;

  /// Título y portada ya conocidos de la tarjeta que abrió esta pantalla.
  final PageSeed? seed;

  @override
  Widget build(BuildContext context) {
    final controller = MusicModeScope.of(context);
    final connection = controller?.connection;
    if (controller == null ||
        controller.transitioning ||
        connection?.status != MusicLinkStatus.linked) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('YouTube Music'),
          actions: const [AccountAction()],
        ),
        body: Center(
          child: controller?.failed == true
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No se pudo comprobar tu cuenta.'),
                    TextButton(
                      onPressed: () => unawaited(controller!.refresh()),
                      child: const Text('Reintentar'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    // La pestaña Biblioteca tiene su propia pantalla (la de Limusic).
    if (surface == MusicSurface.songs) {
      return LibraryScreen(
        key: ValueKey((connection!.generation, controller.revision)),
        controller: controller,
        connection: connection,
      );
    }
    // Buscar también: campo, sugerencias, géneros y resultados de Limusic.
    if (surface == MusicSurface.search) {
      return SearchScreen(
        key: ValueKey((connection!.generation, controller.revision)),
        controller: controller,
        connection: connection,
      );
    }
    final resolved =
        surface == MusicSurface.liked && connection!.usesChannelLikes
        ? MusicSurface.channelLiked
        : surface;
    return _MusicPage(
      key: ValueKey((
        connection!.generation,
        controller.revision,
        resolved,
        playlistId,
      )),
      controller: controller,
      connection: connection,
      surface: resolved,
      playlistId: playlistId,
      seed: seed,
    );
  }
}

/// Cuenta de YouTube Music activa y el historial de escucha, dentro de Cuenta.
class MusicModeSettings extends StatelessWidget {
  const MusicModeSettings({super.key});

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
            'Se borrarán Recientes y Lo más oído de este teléfono.',
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
    final generation = connection?.generation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.headphones),
          title: const Text('YouTube Music'),
          subtitle: Text(
            connection?.account?.name ??
                (controller.failed
                    ? 'Conexión sin verificar'
                    : 'Comprobando conexión…'),
          ),
          trailing: controller.failed
              ? TextButton(
                  onPressed: () => unawaited(controller.refresh()),
                  child: const Text('Reintentar'),
                )
              : null,
        ),
        if (connection?.status == MusicLinkStatus.linked && generation != null)
          ExpansionTile(
            leading: const Icon(Icons.history),
            title: const Text('Historial de escucha'),
            children: [
              SwitchListTile(
                title: const Text('Registrar escuchas en Mysic'),
                value: connection?.account?.historyPaused != true,
                onChanged: controller.updatingActivity
                    ? null
                    : (value) => _activity(
                        context,
                        controller,
                        generation,
                        paused: !value,
                      ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Borrar actividad de Mysic'),
                onTap: controller.updatingActivity
                    ? null
                    : () => _activity(context, controller, generation),
              ),
            ],
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
    this.seed,
  });

  final MusicModeController controller;
  final MusicConnection connection;
  final MusicSurface surface;
  final String? playlistId;
  final PageSeed? seed;

  @override
  ConsumerState<_MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends ConsumerState<_MusicPage>
    with WidgetsBindingObserver {
  final _items = <MusicItem>[];
  final _search = TextEditingController();
  CancelToken? _request;
  String? _cursor;
  String? _query;
  late String? _playlistTitle = widget.seed?.title;
  bool? _playlistPrivate;

  /// La playlist es de la cuenta: sus canciones se pueden quitar.
  bool _editable = false;
  String? _error;
  bool _loading = false;
  bool _wasInBackground = false;
  late MusicSurface _surface = _initialSurface();

  /// En la Biblioteca, si está elegido "Todo" (con las teselas) y no una
  /// sola colección.
  bool _all = true;
  final _scroll = ScrollController();

  /// Datos para los accesos del Inicio y las portadas de la Biblioteca. Se
  /// piden aparte, sin retrasar la primera pintura.
  List<MusicPlaylist> _shortcutPlaylists = const [];

  // El collage de Inicio ("Accesos directos") se compone UNA vez y no cambia
  // mientras se usa la app: lo que se ve al abrir es lo que se guardó la vez
  // anterior, y la composición nueva queda guardada para la próxima apertura.
  // Así no hay un primer collage y otro distinto un instante después.
  final int _dialSeed = DateTime.now().microsecondsSinceEpoch;
  List<MusicItem>? _dialFrozen;
  bool _sideReady = false;
  // Lo más escuchado y lo último que sonó en este teléfono, para el collage.
  List<MusicTrack> _played = const [];
  List<MusicTrack> _recentTracks = const [];

  /// Primera portada de cada colección, para las pastillas de la Biblioteca
  /// ("liked", "artists", "history", "repeat"). Si falta, la pastilla va
  /// solo con su icono.
  final _tileCovers = <String, String>{};
  MusicSurface _initialSurface() {
    final caps = widget.connection.capabilities;
    if (widget.connection.nativeCatalog &&
        (widget.surface == MusicSurface.songs ||
            (widget.surface == MusicSurface.home && !caps.contains('home')))) {
      if (widget.connection.personalization == 'partialMusic' &&
          caps.contains('liked')) {
        return MusicSurface.liked;
      }
      if (caps.contains('musicPlaylists')) return MusicSurface.playlists;
      if (caps.contains('channelLiked')) return MusicSurface.channelLiked;
      return MusicSurface.playlists;
    }
    if (widget.surface == MusicSurface.history &&
        caps.contains('mysicRecents')) {
      return MusicSurface.mysicRecents;
    }
    return widget.surface;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    if (widget.surface == MusicSurface.home) {
      unawaited(_restoreDial());
      // Los atajos fijados y la disposición de Inicio, guardados por cuenta.
      widget.controller.shortcuts.addListener(_homeChanged);
      widget.controller.homeLayout.addListener(_homeChanged);
      unawaited(widget.controller.restoreHome());
    }
    if (_surface != MusicSurface.search) unawaited(_load(reset: true));
    // Las consultas de adorno esperan a que la lista principal haya salido,
    // para no competir con ella por la red ni por el servidor.
    if (_surface != MusicSurface.search) {
      unawaited(Future<void>(_loadSideAfterMain));
    }
  }

  /// El collage tal como quedó la última vez, pintado al instante.
  Future<void> _restoreDial() async {
    final page = await widget.controller.rememberedDial();
    if (!mounted || _dialFrozen != null || page == null) return;
    // Solo páginas completas: un guardado con una página a medias se corta.
    final items = _wholePages(
      page.items
          .where((i) => i is MusicTrack || i is MusicPlaylist)
          .take(_dialSize)
          .toList(),
    );
    if (items.isEmpty) return;
    setState(() => _dialFrozen = items);
  }

  /// Casillas del collage: tres páginas de 3×3 que se deslizan.
  static const _dialSize = SpeedDialGrid.pageSize * 3;

  static List<T> _wholePages<T>(List<T> list) => SpeedDialGrid.wholePages(list);

  /// Compone el collage con lo tuyo: lo más escuchado, lo último que sonó y
  /// lo del Inicio, mezclados, con tus playlists en cada tercera tarjeta.
  List<MusicItem> _composeDial() {
    final hasShelves = _items.any((item) => item.shelfTitle != null);
    final firstShelf = _items.isEmpty ? null : _items.first.shelfTitle;
    // Solo del primer estante del Inicio: lo que entra en el collage deja de
    // pintarse en su estante, y los demás deben quedar enteros.
    final liked = _items
        .whereType<MusicTrack>()
        .where(
          (t) =>
              _canPlayTrack(t) && (!hasShelves || t.shelfTitle == firstShelf),
        )
        .take(_dialSize)
        .toList();
    // Canciones de los demás estantes del Inicio: rellenan el collage cuando lo
    // propio (lo más oído, lo reciente, el primer estante) no llega a las 27.
    // No se quitan de su estante: allí siguen estando.
    final others = hasShelves
        ? _items
              .whereType<MusicTrack>()
              .where((t) => _canPlayTrack(t) && t.shelfTitle != firstShelf)
              .take(_dialSize)
              .toList()
        : const <MusicTrack>[];
    final random = Random(_dialSeed);
    List<T> mixed<T>(List<T> list) => [...list]..shuffle(random);
    final tracks = <MusicTrack>[];
    final seen = <String>{};
    final sources = [
      mixed(_played),
      mixed(_recentTracks),
      mixed(liked),
      mixed(others),
    ];
    for (
      var round = 0;
      round < _dialSize && tracks.length < _dialSize;
      round++
    ) {
      for (final source in sources) {
        if (round >= source.length || tracks.length >= _dialSize) continue;
        final track = source[round];
        if (_canPlayTrack(track) && seen.add(track.id)) tracks.add(track);
      }
    }
    final lists = mixed(_shortcutPlaylists);
    final dial = <MusicItem>[];
    var nextTrack = 0, nextList = 0;
    while (dial.length < _dialSize &&
        (nextTrack < tracks.length || nextList < lists.length)) {
      final listSlot = dial.length % 3 == 2 && nextList < lists.length;
      dial.add(
        listSlot || nextTrack >= tracks.length
            ? lists[nextList++]
            : tracks[nextTrack++],
      );
    }
    // Páginas completas: nunca una con tres casillas y el resto vacío.
    return _wholePages(dial);
  }

  /// Cuando ya llegaron los datos: si aún no había collage guardado se muestra
  /// este, y en todo caso se guarda para la próxima apertura.
  void _settleDial({bool force = false}) {
    if (!mounted || widget.surface != MusicSurface.home) return;
    _sideReady = true;
    final fresh = _composeDial();
    if (fresh.isNotEmpty) {
      widget.controller.rememberDial({
        'items': [for (final item in fresh) _dialJson(item)],
        'nextCursor': null,
        'excludedCount': 0,
      });
    }
    setState(() {
      // El guardado se respeta (no hay un collage y otro distinto al instante),
      // salvo que sea más pobre que el de ahora: uno hecho sin datos, o con
      // pocas canciones, no debe quedarse para siempre.
      final poorer = (_dialFrozen?.length ?? 0) < fresh.length;
      if ((_dialFrozen == null || force || poorer) && fresh.isNotEmpty) {
        _dialFrozen = fresh;
      }
    });
  }

  static Map<String, dynamic> _dialJson(MusicItem item) => switch (item) {
    MusicTrack() => {
      'kind': 'track',
      'id': item.id,
      'title': item.title,
      'artist': item.artist,
      'durationSeconds': item.durationSeconds,
      'playback': 'native',
      'thumbnailUrl': item.thumbnailUrl,
      'artistId': item.artistId,
      'albumId': item.albumId,
      'albumName': item.albumName,
    },
    MusicPlaylist() => {
      'kind': 'playlist',
      'id': item.id,
      'title': item.title,
      'private': item.isPrivate,
      'thumbnailUrl': item.thumbnailUrl,
    },
    _ => {'kind': 'unknown'},
  };

  /// Envuelve una fila o tarjeta de canción para empezar a resolver su audio
  /// en cuanto el dedo la toca.
  Widget _warm(MusicTrack track, Widget child) => TouchWarm(
    onTouch: () => _touchTrack(track),
    onLinger: () => _warmLingering(track),
    child: child,
  );

  /// La fila lleva un momento a la vista (el usuario se detuvo en ella): se
  /// adelanta su audio, para que las canciones que se alcanzan desplazando la
  /// lista, más allá de las primeras, no tarden en sonar al tocarlas.
  void _warmLingering(MusicTrack track) {
    if (!mounted || !_canPlayTrack(track)) return;
    final generation = widget.connection.generation;
    if (generation == null ||
        !widget.controller.isCurrent(generation) ||
        !ref.exists(trackPlaybackControllerProvider)) {
      return;
    }
    ref.read(trackPlaybackControllerProvider).warmTracks([
      widget.controller.playbackTrack(generation, track),
    ]);
  }

  String? _touchedId;
  DateTime _touchedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// El dedo acaba de tocar [track]: se empieza a resolver su audio antes de
  /// que se levante. Se ignora el mismo toque repetido en menos de 1 s.
  void _touchTrack(MusicTrack track) {
    if (!_canPlayTrack(track)) return;
    final now = DateTime.now();
    if (_touchedId == track.id &&
        now.difference(_touchedAt) < const Duration(seconds: 1)) {
      return;
    }
    _touchedId = track.id;
    _touchedAt = now;
    final generation = widget.connection.generation;
    if (generation == null ||
        !widget.controller.isCurrent(generation) ||
        !ref.exists(trackPlaybackControllerProvider)) {
      return;
    }
    ref
        .read(trackPlaybackControllerProvider)
        .touchTrack(widget.controller.playbackTrack(generation, track));
  }

  /// Pide la siguiente página cuando faltan menos de dos pantallas para el
  /// final: sin tope de canciones ni botón, la lista crece mientras el
  /// servidor tenga continuación. Una sola petición a la vez.
  /// Solo avanza cuando la persona desplaza la lista; si no, una lista corta
  /// encadenaría páginas sin parar (y el Inicio se "actualizaría" solo).
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.userScrollDirection == ScrollDirection.idle) return;
    _nearEnd();
  }

  void _nearEnd() {
    if (_cursor == null || _loading || _error != null || !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    if (position.extentAfter < position.viewportDimension * 2) {
      unawaited(_load(reset: false));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _wasInBackground = true;
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      if (widget.surface == MusicSurface.songs ||
          _surface == MusicSurface.playlists ||
          _surface == MusicSurface.playlist) {
        unawaited(_load(reset: true, keepItems: true));
      }
    }
  }

  Future<void> _load({
    required bool reset,
    String? query,
    bool keepItems = false,
  }) async {
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
      if (reset && !keepItems) {
        _items.clear();
        _cursor = null;
      }
      if (query != null) _query = query;
      // Lo que ya se vio de esta pantalla en la sesión se pinta enseguida;
      // la respuesta del servidor lo sustituye al llegar.
      if (reset && _items.isEmpty && _query == null) {
        final seen = widget.controller.recalledPage(
          generation,
          _surface,
          playlistId: widget.playlistId,
        );
        if (seen != null && seen.items.isNotEmpty) {
          // Rastro para medir, como los audio_* del reproductor.
          debugPrint(
            'page_seed source=memory surface=${_surface.name} '
            'items=${seen.items.length}',
          );
          _items.addAll(seen.items);
          _seeded = true;
          _playlistTitle = seen.title ?? seen.playlist?.title ?? _playlistTitle;
          _playlistPrivate = seen.playlist?.isPrivate ?? _playlistPrivate;
        }
      }
    });
    if (_seeded && _usesMosaic) unawaited(_pickMosaic());
    // Inicio se pinta enseguida con lo último que se guardó de él; la
    // respuesta del servidor lo sustituye al llegar.
    // Sin nada en memoria, se prueba con lo guardado en disco: así también
    // se pinta enseguida tras cerrar y reabrir la app.
    final first = reset && _query == null;
    if (first && _items.isEmpty) unawaited(_seedFromDisk(generation, request));
    try {
      var page = _mood != null && _query != null
          ? await widget.controller.ask(
              generation,
              (client) => client.moodHome(
                _query!,
                cursor: reset ? null : _cursor,
                cancelToken: request,
              ),
            )
          : _catalogSearch
          ? await widget.controller.publicSearch(
              generation,
              _query ?? '',
              _searchType,
              cancelToken: request,
            )
          : await widget.controller.page(
              generation,
              _surface,
              playlistId: widget.playlistId,
              query: _query,
              cursor: reset ? null : _cursor,
              cancelToken: request,
              remember: first,
            );
      final incoming = [...page.items];
      final collectPlaylists =
          widget.connection.isDirect && _surface == MusicSurface.playlists;
      final followed = <String>{};
      // Inicio muestra su primera página enseguida y pide las siguientes en
      // segundo plano hasta llenar el collage (ver _fillHome).
      final fillHome =
          widget.surface == MusicSurface.home &&
          widget.connection.nativeCatalog;
      while (((collectPlaylists && incoming.length < 20) ||
              (widget.connection.channelOnly && incoming.isEmpty)) &&
          page.nextCursor != null &&
          followed.length < 3 &&
          followed.add(page.nextCursor!) &&
          mounted &&
          request == _request &&
          widget.controller.isCurrent(generation)) {
        try {
          page = await widget.controller.page(
            generation,
            _surface,
            playlistId: widget.playlistId,
            query: _query,
            cursor: page.nextCursor,
            cancelToken: request,
          );
          incoming.addAll(page.items);
        } on ApiFailure {
          // Keep the successful pages and let the user retry their continuation.
          if (incoming.isEmpty) rethrow;
          break;
        }
      }
      if (!mounted ||
          request != _request ||
          !widget.controller.isCurrent(generation)) {
        return;
      }
      setState(() {
        _cursor = page.nextCursor;
        _editable = _editable || page.editable;
        _ownKnown = true;
        if ((reset && keepItems) || _seeded) _items.clear();
        _seeded = false;
        _items.addAll(incoming);
        _playlistTitle = page.title ?? page.playlist?.title ?? _playlistTitle;
        _playlistPrivate = page.playlist?.isPrivate ?? _playlistPrivate;
      });
      // Inicio adelanta su audio más tarde, tras su primera pintura (ver
      // _loadSideAfterMain). Se mira la pestaña pedida, no la superficie
      // resuelta: con el canal de YouTube, Inicio se sirve con otra.
      if (reset && widget.surface != MusicSurface.home) _warmVisible();
      if (reset && _usesMosaic) unawaited(_pickMosaic());
      if (fillHome && _cursor != null) unawaited(Future(_fillHome));
    } on ApiFailure catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = switch (error.code) {
            'INVALID_CURSOR' ||
            'CURSOR_EXPIRED' => 'La página caducó. Actualiza la lista.',
            'YOUTUBE_QUOTA' || 'TOO_MANY_REQUESTS' =>
              'Se alcanzó el límite de consultas. Vuelve a intentarlo más tarde.',
            'DESKTOP_EXPIRED' ||
            'DESKTOP_MUSIC_LINK' ||
            'DESKTOP_SERVICE' ||
            'DESKTOP_NETWORK' ||
            'DESKTOP_HOME' => error.message,
            'MUSIC_ACCESS_UNVERIFIED' =>
              'Aún no se pudo verificar la biblioteca musical.',
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
      if (mounted && request == _request) {
        setState(() => _loading = false);
        // Una página corta no llega a provocar desplazamiento: se comprueba
        // tras pintarla si aún falta lista por llenar.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Solo si la lista aún no llena la pantalla y no se puede desplazar.
          if (mounted &&
              _scroll.hasClients &&
              _scroll.position.maxScrollExtent <= 0) {
            _nearEnd();
          }
        });
      }
    }
  }

  // Hay elementos de Inicio leídos del disco, a la espera del servidor.
  bool _seeded = false;

  // Ya llegó una página del servidor: se sabe si la playlist es propia.
  bool _ownKnown = false;

  /// Todas las canciones de la playlist: carga las páginas que falten (hasta
  /// 40), para descargarla entera.
  Future<List<MusicTrack>> _loadAllTracks() async {
    for (var round = 0; round < 40; round++) {
      if (!mounted || _cursor == null || _error != null) break;
      if (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      await _load(reset: false);
    }
    return _items.whereType<MusicTrack>().toList();
  }

  Future<void> _seedFromDisk(String generation, CancelToken request) async {
    final page = await widget.controller.rememberedPage(
      generation,
      _surface,
      playlistId: widget.playlistId,
    );
    if (page == null ||
        page.items.isEmpty ||
        !mounted ||
        request != _request ||
        !_loading ||
        _items.isNotEmpty) {
      return;
    }
    debugPrint(
      'page_seed source=disk surface=${_surface.name} items=${page.items.length}',
    );
    setState(() {
      _items.addAll(page.items);
      _seeded = true;
      _playlistTitle = page.title ?? page.playlist?.title ?? _playlistTitle;
      _playlistPrivate = page.playlist?.isPrivate ?? _playlistPrivate;
    });
    if (_usesMosaic) unawaited(_pickMosaic());
    // Lo que se ve ya se puede tocar: su audio se adelanta sin esperar a
    // que el servidor confirme la página.
    _warmVisible();
  }

  Future<void> _refreshPage() async {
    if (_loading) return;
    await _load(reset: true, keepItems: true);
    // Al actualizar a mano, el collage también se renueva.
    if (widget.surface == MusicSurface.home && mounted) {
      await _loadSideData();
      _settleDial(force: true);
    }
  }

  /// Completa el collage del Inicio con páginas sucesivas, una a una, sin
  /// retrasar la primera pintura. Se detiene si la pantalla cambia.
  Future<void> _fillHome() async {
    for (var round = 0; round < 3; round++) {
      if (!mounted ||
          _loading ||
          _cursor == null ||
          _items.whereType<MusicTrack>().length >= 10) {
        return;
      }
      await _load(reset: false);
    }
  }

  // Los ambientes de Inicio de YouTube Music: cada uno es la misma página con
  // su clave (las de Limusic, `HOME_PARAMS_*`).
  static const _moods = [
    (
      'Relax',
      'ggM8SgQIBxADSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB',
    ),
    (
      'Dormir',
      'ggM8SgQIBxABSgQIBRADSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB',
    ),
    (
      'Energía',
      'ggM8SgQIBxABSgQIBRABSgQICRADSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB',
    ),
    (
      'Tristeza',
      'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChADSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB',
    ),
    (
      'Romance',
      'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRADSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB',
    ),
    (
      'Buen ánimo',
      'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBADSgQIBBABSgQIDhABSgQIAxABSgQIBhAB',
    ),
    (
      'Entreno',
      'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBADSgQIDhABSgQIAxABSgQIBhAB',
    ),
    (
      'Fiesta',
      'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhADSgQIAxABSgQIBhAB',
    ),
    (
      'Trayecto',
      'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxADSgQIBhAB',
    ),
    (
      'Concentración',
      'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAD',
    ),
  ];
  String? _mood;

  /// Qué busca la pestaña Buscar: canciones, artistas o álbumes.
  String _searchType = 'song';

  /// Búsquedas recientes de esta cuenta: viven en su controlador, así que no
  /// se mezclan al cambiar de cuenta ni de fuente musical.
  List<String> get _recent => widget.controller.recentSearches;

  bool get _catalogSearch =>
      _surface == MusicSurface.search &&
      _searchType != 'song' &&
      widget.controller.hasPublicCatalog;

  void _setSearchType(String type) {
    if (_searchType == type) return;
    setState(() => _searchType = type);
    final query = (_query ?? _search.text).trim();
    if (query.isNotEmpty) unawaited(_load(reset: true, query: query));
  }

  /// Elige un ambiente (o, con null o el mismo, vuelve al Inicio de siempre).
  /// La clave viaja en `_query`: marca la página como distinta de la de
  /// Inicio, que así ni se guarda ni se siembra de lo guardado.
  void _pickMood(String? label, [String? params]) {
    final clear = label == null || _mood == label;
    if (clear && _mood == null) return;
    setState(() {
      _mood = clear ? null : label;
      _surface = _initialSurface();
      _query = clear ? null : params;
    });
    unawaited(_load(reset: true, query: clear ? null : params));
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
    _recent
      ..remove(query)
      ..insert(0, query);
    if (_recent.length > 10) _recent.removeRange(10, _recent.length);
    unawaited(_load(reset: true, query: query));
  }

  bool _canPlayTrack(MusicTrack track) => widget.connection.isPreview
      ? widget.connection.capabilities.contains('playback') && track.canPreview
      : (widget.controller.deviceAudio(track.id) != null ||
            (widget.connection.capabilities.contains('playback') &&
                track.canPlayInMysic));

  String _addToQueue(Iterable<MusicTrack> tracks, {required bool next}) {
    final music = widget.controller;
    final generation = widget.connection.generation!;
    if (!music.isCurrent(generation)) return 'Cambió la conexión.';
    final added = ref
        .read(trackPlaybackControllerProvider)
        .queueConnected(
          tracks
              .where(_canPlayTrack)
              .map((track) => music.playbackTrack(generation, track)),
          next: next,
          listenForTrack: () => music.listenForTrack(generation),
        );
    if (!added) return 'La cola no cambió';
    return next
        ? 'Se reproducirá a continuación'
        : 'Añadido al final de la cola';
  }

  /// Cada tipo de elemento tiene su propia hoja: la de una canción lleva
  /// cabecera y acciones rápidas; las de playlist, álbum y artista, su lista.
  void _openSheet(MusicItem item) => unawaited(
    showItemMenu(
      context,
      ref,
      item,
      // En una playlist propia la canción se puede quitar de ella.
      playlistId: _editable && widget.surface == MusicSurface.playlist
          ? widget.playlistId
          : null,
      onChanged: () => unawaited(_refreshPage()),
    ),
  );

  /// Hoja de la playlist o el álbum que se está viendo (Limusic
  /// `PlaylistBottomSheet`): «Reproducir» con aleatorio y las acciones sobre
  /// todas sus canciones.
  void _collectionSheet() {
    final id = widget.playlistId;
    // Una playlist o un álbum de YouTube Music: su hoja completa (radio,
    // guardar, atajo, editar y eliminar si es propia).
    if (id != null &&
        (widget.surface == MusicSurface.playlist ||
            widget.surface == MusicSurface.album)) {
      final title = _playlistTitle ?? widget.seed?.title ?? '';
      final cover = widget.seed?.imageUrl;
      unawaited(
        showItemMenu(
          context,
          ref,
          widget.surface == MusicSurface.album
              ? MusicAlbum(id, title, thumbnailUrl: cover)
              : MusicPlaylist(
                  id,
                  title,
                  _playlistPrivate == true,
                  thumbnailUrl: cover,
                ),
          onChanged: () => unawaited(_refreshPage()),
        ),
      );
      return;
    }
    final tracks = _items.whereType<MusicTrack>().where(_canPlayTrack).toList();
    if (tracks.isEmpty) return;
    final link = id == null
        ? null
        : widget.surface == MusicSurface.album
        ? Uri.https('music.youtube.com', '/browse/$id')
        : Uri.https('music.youtube.com', '/playlist', {'list': id});
    void say(String message) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }

    showItemSheet(
      context,
      onPlay: () => _play(tracks.first),
      onShuffle: () => _play(tracks.first, shuffled: true),
      rows: () => [
        SheetRow(
          icon: Icons.play_circle_outline,
          label: 'Reproducir a continuación',
          onTap: () => say(_addToQueue(tracks, next: true)),
        ),
        SheetRow(
          icon: Icons.queue_music,
          label: 'Añadir a la cola',
          onTap: () => say(_addToQueue(tracks, next: false)),
        ),
        if (link != null)
          SheetRow(
            icon: Icons.share,
            label: 'Compartir',
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: link.toString()));
              say('Enlace copiado');
            },
          ),
      ],
    );
  }

  /// Reproduce [selected] con la cola [from] (por defecto, las canciones de
  /// la pantalla). El collage de Inicio pasa la suya: sus canciones del
  /// historial no están en la lista de la pantalla.
  void _play(
    MusicTrack selected, {
    bool shuffled = false,
    List<MusicTrack>? from,
  }) {
    final generation = widget.connection.generation!;
    if (!widget.controller.isCurrent(generation)) return;
    final tracks = (from ?? _items.whereType<MusicTrack>())
        .where(_canPlayTrack)
        .toList();
    final selectedIndex = tracks.indexOf(selected);
    if (selectedIndex < 0) return;
    // Una canción suelta (Inicio, búsqueda, artista) es la cola de esa sola
    // canción: lo que sigue lo pone la radio. Una lista (playlist, álbum, Me
    // gusta, historial) pasa entera a la cola, con lo ya pasado detrás.
    final single =
        !shuffled &&
        (from != null ||
            widget.surface == MusicSurface.home ||
            widget.surface == MusicSurface.search ||
            widget.surface == MusicSurface.artist);
    final start = single
        ? selectedIndex
        : selectedIndex < TrackPlaybackController.maxQueue
        ? 0
        : selectedIndex - 50;
    final queue = tracks
        .skip(start)
        .take(single ? 1 : TrackPlaybackController.maxQueue)
        .map((item) => widget.controller.playbackTrack(generation, item))
        .toList();
    final music = widget.controller;
    final controller = ref.read(trackPlaybackControllerProvider);
    unawaited(
      controller.playQueue(
        queue,
        initialIndex: selectedIndex - start,
        shuffled: shuffled,
        listenForTrack: () => music.listenForTrack(generation),
      ),
    );
    context.push('/player');
  }

  String get _title => switch (widget.surface) {
    MusicSurface.home => 'Inicio',
    MusicSurface.songs => 'Biblioteca',
    MusicSurface.liked => 'Me gusta de YouTube Music',
    MusicSurface.channelLiked => 'Me gusta de mi canal',
    MusicSurface.albums => 'Álbumes',
    MusicSurface.album => _playlistTitle ?? 'Álbum',
    MusicSurface.playlist => _playlistTitle ?? 'Playlist',
    MusicSurface.search => 'Buscar',
    MusicSurface.history => 'Recientes',
    MusicSurface.mysicRecents => 'Recientes',
    MusicSurface.onRepeat => 'Lo más oído',
    MusicSurface.artist => 'Más de este canal',
    MusicSurface.artists => 'Canales musicales que sigues',
    MusicSurface.playlists => 'Biblioteca',
  };

  @override
  Widget build(BuildContext context) {
    final account = widget.connection.account!;
    final isHome = widget.surface == MusicSurface.home;
    // La playlist lleva su propia cabecera (mosaico de portadas, título
    // grande y botones flotantes) en lugar de la barra superior.
    final isPlaylist = widget.surface == MusicSurface.playlist;
    final isLiked = _isLiked;
    final isRecent = _isRecent;
    final isRepeat = widget.surface == MusicSurface.onRepeat;
    final hasHero =
        isPlaylist ||
        isLiked ||
        isRecent ||
        widget.surface == MusicSurface.onRepeat;
    // Cuadrado en vertical; en horizontal o en tableta se limita a algo más
    // de media pantalla para que las canciones no queden fuera de la vista.
    final screen = MediaQuery.sizeOf(context);
    final mosaic = screen.width < screen.height * .55
        ? screen.width
        : screen.height * .55;
    final hasShelves = isHome && _items.any((item) => item.shelfTitle != null);
    final firstPlayable = _items
        .whereType<MusicTrack>()
        .where(_canPlayTrack)
        .firstOrNull;
    // La barra va encima del contenido, transparente arriba del todo y con
    // desenfoque al desplazar (Limusic: Haze ultraThin).
    final bar = AppBar(
      backgroundColor: Colors.transparent,
      flexibleSpace: _BarBlur(scroll: _scroll),
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
          onPressed: _loading ? null : _refreshPage,
        ),
        if (widget.surface != MusicSurface.playlist &&
            widget.surface != MusicSurface.history)
          const AccountAction(),
      ],
    );
    // Inicio lleva la cabecera de las pestañas, la misma de Biblioteca y
    // Buscar; su fondo aparece al desplazar, para no tapar la carátula.
    final tabBar = TabTopBar(
      title: _title,
      scroll: _scroll,
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.sync_rounded),
          onPressed: _loading ? null : _refreshPage,
        ),
        if (widget.connection.capabilities.contains('history') ||
            widget.connection.capabilities.contains('mysicRecents'))
          IconButton(
            tooltip: 'Abrir Recientes',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/history'),
          ),
        const AccountAction(),
      ],
    );
    final barHeight = isHome ? TabTopBar.height : kToolbarHeight;
    return Scaffold(
      body: Stack(
        children: [
          // Fondo del Inicio: la carátula que suena, muy desenfocada.
          if (isHome && _layout.backdrop)
            Positioned(top: 0, left: 0, right: 0, child: _homeBackdrop()),
          if (isLiked || isRecent || isRepeat)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LikedHero(
                scroll: _scroll,
                height: mosaic,
                icon: isRepeat
                    ? Icons.repeat_rounded
                    : isRecent
                    ? Icons.history_rounded
                    : Icons.favorite_rounded,
              ),
            ),
          if (_usesMosaic)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: PlaylistMosaic(
                // Mientras se eligen las portadas, la de la tarjeta tocada.
                covers:
                    _mosaic ??
                    [if (widget.seed?.imageUrl case final String url) url],
                scroll: _scroll,
                height: mosaic,
              ),
            ),
          SafeArea(
            top: false,
            child: RefreshIndicator(
              onRefresh: _refreshPage,
              edgeOffset: MediaQuery.paddingOf(context).top + barHeight,
              child: _LazyColumn(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  16,
                  // En la playlist el texto empieza sobre el fundido del mosaico.
                  hasHero
                      ? mosaic * .66
                      : MediaQuery.paddingOf(context).top + barHeight + 8,
                  16,
                  20,
                ),
                children: [
                  if (isHome)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        [
                          switch (DateTime.now().hour) {
                            >= 5 && < 12 => 'Buenos días',
                            >= 12 && < 20 => 'Buenas tardes',
                            _ => 'Buenas noches',
                          },
                          // Con el nombre de pila, como el saludo de Limusic.
                          ?account.name
                              .trim()
                              .split(RegExp(r'\s+'))
                              .where((word) => word.isNotEmpty)
                              .firstOrNull,
                        ].join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  // Ambientes de Inicio (Limusic): lo primero, el botón de
                  // «Editar inicio», que nunca se va; luego «Todo» y cada
                  // ambiente, que carga el Inicio de YouTube Music con su clave.
                  // Con los chips apagados queda solo el botón, con su nombre;
                  // mientras hay un ambiente elegido siguen ahí: «Todo» es la
                  // salida.
                  if (isHome && widget.connection.nativeCatalog)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          children: [
                            if (_layout.chips || _mood != null) ...[
                              Center(
                                child: Material(
                                  type: MaterialType.transparency,
                                  shape: CircleBorder(
                                    side: BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () => unawaited(
                                      showEditHome(context, widget.controller),
                                    ),
                                    child: Tooltip(
                                      message: 'Editar inicio',
                                      child: SizedBox.square(
                                        dimension: 32,
                                        child: Icon(
                                          Icons.tune_rounded,
                                          size: 18,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              LibraryChip(
                                label: 'Todo',
                                selected: _mood == null,
                                onTap: () => _pickMood(null),
                              ),
                              for (final (label, params) in _moods) ...[
                                const SizedBox(width: 4),
                                LibraryChip(
                                  label: label,
                                  selected: _mood == label,
                                  onTap: () => _pickMood(label, params),
                                ),
                              ],
                            ] else
                              LibraryChip(
                                label: 'Editar inicio',
                                icon: Icons.tune_rounded,
                                selected: false,
                                onTap: () => unawaited(
                                  showEditHome(context, widget.controller),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (hasHero) _heroHeader(context, firstPlayable),
                  if (_surface == MusicSurface.mysicRecents &&
                      widget.connection.capabilities.contains('onRepeat'))
                    ListTile(
                      leading: const Icon(Icons.repeat),
                      title: const Text('Lo más oído'),
                      subtitle: const Text('Últimos 30 días'),
                      onTap: () => context.push('/music/repeat'),
                    ),
                  // Solo el ambiente elegido lleva título; el resto de Inicio ya
                  // se explica solo.
                  if (isHome && !hasShelves && _mood != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Ambiente · $_mood'),
                    ),
                  if (widget.surface == MusicSurface.songs) _libraryChips(),
                  // Teselas fijadas de la Biblioteca, como las de Limusic: accesos
                  // a las colecciones que viven en su propia pantalla. Solo en
                  // "Todo".
                  if (widget.surface == MusicSurface.songs && _all)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LibraryTiles(
                        tiles: [
                          if (widget.connection.capabilities.contains(
                                'liked',
                              ) ||
                              widget.connection.capabilities.contains(
                                'channelLiked',
                              ))
                            (
                              icon: Icons.favorite_rounded,
                              label: 'Tus Me gusta',
                              caption: 'Tus favoritas',
                              onTap: () => context.push('/music/liked'),
                              coverUrl: _tileCovers['liked'],
                            ),
                          if (widget.connection.capabilities.contains(
                            'artists',
                          ))
                            (
                              icon: Icons.people_alt_rounded,
                              label: 'Artistas',
                              caption: 'Los que sigues',
                              onTap: () => context.push('/music/artists'),
                              coverUrl: _tileCovers['artists'],
                            ),
                          if (widget.connection.capabilities.contains(
                                'history',
                              ) ||
                              widget.connection.capabilities.contains(
                                'mysicRecents',
                              ))
                            (
                              icon: Icons.history_rounded,
                              label: 'Recientes',
                              caption: 'Tu historial',
                              onTap: () => context.push('/history'),
                              coverUrl: _tileCovers['history'],
                            ),
                          if (widget.connection.capabilities.contains(
                            'onRepeat',
                          ))
                            (
                              icon: Icons.repeat_rounded,
                              label: 'Lo más oído',
                              caption: 'Últimos 30 días',
                              onTap: () => context.push('/music/repeat'),
                              coverUrl: _tileCovers['repeat'],
                            ),
                        ],
                      ),
                    ),
                  // En Inicio el collage ya da acceso a reproducir; la fila de
                  // acciones solo acompaña a las listas.
                  if (widget.connection.nativeCatalog &&
                      !isHome &&
                      !hasHero &&
                      firstPlayable != null &&
                      const {
                        MusicSurface.songs,
                        MusicSurface.liked,
                        MusicSurface.channelLiked,
                        MusicSurface.playlist,
                        MusicSurface.album,
                        MusicSurface.artist,
                        MusicSurface.onRepeat,
                      }.contains(_surface))
                    // Como la cabecera de álbum de Limusic: Aleatorio sin fondo y un
                    // Play circular de 52 dp relleno del acento, a la derecha.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_items.whereType<MusicTrack>().length} canciones',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Aleatorio',
                          iconSize: 26,
                          style: IconButton.styleFrom(
                            fixedSize: const Size.square(52),
                          ),
                          icon: const Icon(Icons.shuffle_rounded),
                          onPressed: () => _play(firstPlayable, shuffled: true),
                        ),
                        IconButton.filled(
                          tooltip: 'Reproducir',
                          iconSize: 30,
                          style: IconButton.styleFrom(
                            fixedSize: const Size.square(52),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          onPressed: () => _play(firstPlayable),
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
                  if (_surface == MusicSurface.search && !isHome)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: TextField(
                        controller: _search,
                        maxLength: 120,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          labelText: widget.connection.nativeCatalog
                              ? 'Buscar música por canción o artista'
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
                  if (_surface == MusicSurface.search &&
                      !isHome &&
                      widget.controller.hasPublicCatalog)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final (type, label) in const [
                            ('song', 'Canciones'),
                            ('artist', 'Artistas'),
                            ('album', 'Álbumes'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _searchType == type,
                              showCheckmark: false,
                              onSelected: (_) => _setSearchType(type),
                            ),
                        ],
                      ),
                    ),
                  // Búsqueda en reposo: recientes y géneros, como en Limusic.
                  if (_surface == MusicSurface.search &&
                      !isHome &&
                      _query == null &&
                      _items.isEmpty &&
                      !_loading) ...[
                    if (_recent.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Búsquedas recientes',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(_recent.clear),
                              child: const Text('Borrar'),
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final text in _recent)
                            ActionChip(
                              label: Text(text),
                              onPressed: () {
                                _search.text = text;
                                _searchFor(text);
                              },
                            ),
                        ],
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 18, bottom: 10),
                      child: Text(
                        'Géneros y ambientes',
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(fontSize: 20),
                      ),
                    ),
                    GenreGrid(
                      onPick: (label, query) {
                        _search.text = query;
                        _searchFor(query);
                      },
                    ),
                  ],
                  if ((_surface == MusicSurface.history ||
                          _surface == MusicSurface.mysicRecents ||
                          _surface == MusicSurface.onRepeat) &&
                      account.historyPaused)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('El historial está pausado.'),
                    ),
                  ..._itemRows(context, isHome, hasShelves, firstPlayable),
                  // Con la lista vacía, un esqueleto con la forma del contenido; al
                  // añadir páginas, el indicador de siempre.
                  if (_loading && _items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: isHome
                          ? (_dialFrozen == null
                                ? const SkeletonGrid()
                                : const SizedBox.shrink())
                          : const SkeletonRows(),
                    )
                  else if (_loading)
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
                  if (!_loading &&
                      _error == null &&
                      _items.isEmpty &&
                      _cursor == null &&
                      (_surface != MusicSurface.search || _query != null))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        !widget.connection.capabilities.contains(_surface.name)
                            ? 'Esta función no está habilitada para la cuenta.'
                            : _surface == MusicSurface.onRepeat
                            ? 'Aquí aparecerán las canciones que escuches al menos dos veces en Mysic.'
                            : _surface == MusicSurface.history ||
                                  _surface == MusicSurface.mysicRecents
                            ? 'Aún no hay escuchas.'
                            : _surface == MusicSurface.channelLiked
                            ? 'Este canal todavía no tiene Me gusta musicales disponibles.'
                            : _surface == MusicSurface.playlists &&
                                  widget.connection.channelOnly
                            ? 'No encontramos playlists con música en este canal.'
                            : 'No hay resultados.',
                      ),
                    ),
                  // Sin botón: la lista pide sola la siguiente página al
                  // acercarse al final (ver _nearEnd), como YouTube Music.
                  if (_cursor != null && !_loading && _error == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Con altura propia: sin ella el fondo del desenfoque no tiene tamaño
          // acotado y no se dibuja (el AppBar espera una altura que le da el
          // Scaffold cuando va en ppBar).
          // Al pasar la cabecera, una barra con el título tapa lo que sube
          // bajo la barra de estado y los botones.
          if (hasHero)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top + 64,
              child: _PlaylistBar(
                scroll: _scroll,
                // Opaca antes de que el título grande llegue debajo: así no se
                // solapan los dos títulos mientras la barra se pinta.
                start: mosaic * .5 - 70,
                title: _heroTitle,
              ),
            ),
          if (hasHero)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 12,
              right: 12,
              child: _playlistControls(context),
            )
          else if (isHome)
            Positioned(top: 0, left: 0, right: 0, child: tabBar)
          else
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top + kToolbarHeight,
              child: bar,
            ),
        ],
      ),
    );
  }

  // Portadas elegidas para el mosaico; null mientras se eligen.
  List<String>? _mosaic;
  int _mosaicRequest = 0;

  /// Elige las portadas del mosaico: las cuatro primeras de la lista que no
  /// traen franjas negras propias (vídeos apaisados), para que se vea como un
  /// collage de carátulas. Si no hay cuatro limpias se completa con el resto.
  Future<void> _pickMosaic() async {
    final request = ++_mosaicRequest;
    final candidates = <String>[];
    for (final track in _items.whereType<MusicTrack>()) {
      final url = track.thumbnailUrl;
      if (url != null && !candidates.contains(url)) candidates.add(url);
      if (candidates.length == 16) break;
    }
    final clean = <String>[];
    for (final url in candidates) {
      if (!await CoverColor.hasBars(TrackArtwork.sizedUrl(url, 360))) {
        clean.add(url);
        if (clean.length == 4) break;
      }
    }
    if (!mounted || request != _mosaicRequest) return;
    final chosen = [
      ...clean,
      ...candidates.where((url) => !clean.contains(url)),
    ].take(4).toList();
    setState(() => _mosaic = chosen);
  }

  static String _length(int seconds) {
    final hours = seconds ~/ 3600, minutes = seconds % 3600 ~/ 60;
    return hours > 0 ? '$hours h $minutes min' : '$minutes min';
  }

  // Playlist y "Lo más oído" llevan mosaico de portadas; "Me gusta", un icono
  // grande sobre un degradado del color de la app.
  // En el modo canal, "Me gusta" llega a esta pantalla como channelLiked.
  bool get _isLiked =>
      widget.surface == MusicSurface.liked ||
      widget.surface == MusicSurface.channelLiked;

  bool get _isRecent =>
      widget.surface == MusicSurface.history ||
      widget.surface == MusicSurface.mysicRecents;

  bool get _usesMosaic => widget.surface == MusicSurface.playlist;

  String get _heroTitle => switch (widget.surface) {
    MusicSurface.liked || MusicSurface.channelLiked => 'Tus Me gusta',
    MusicSurface.history || MusicSurface.mysicRecents => 'Recientes',
    MusicSurface.onRepeat => 'Lo más oído',
    _ => _title,
  };

  static String _plural(int n, String one, String many) =>
      '$n ${n == 1 ? one : many}';

  /// Cabecera sobre el fundido de la imagen (como la de Limusic): tipo en
  /// versalitas, título grande con Aleatorio y Play, y debajo el dueño o los
  /// totales. En "Lo más oído" no hay dueño: son las canciones y sus escuchas.
  Widget _heroHeader(BuildContext context, MusicTrack? firstPlayable) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final muted = colors.onSurfaceVariant;
    final repeat = widget.surface == MusicSurface.onRepeat;
    final liked = _isLiked;
    final recent = _isRecent;
    final tracks = _items.whereType<MusicTrack>().toList();
    final seconds = tracks.fold<int>(
      0,
      (sum, track) =>
          sum + (track.durationSeconds > 0 ? track.durationSeconds : 0),
    );
    final plays = tracks.fold<int>(
      0,
      (sum, track) => sum + (track.playCount ?? 0),
    );
    final count = tracks.isEmpty
        ? null
        // Con más páginas por cargar, el número es un mínimo.
        : '${tracks.length}${_cursor != null ? '+' : ''} '
              '${tracks.length == 1 ? 'canción' : 'canciones'}';
    final details = [
      ?count,
      if (repeat && plays > 0) _plural(plays, 'escucha', 'escuchas'),
      if (!repeat && seconds >= 60) _length(seconds),
    ];
    final kicker = repeat
        ? 'TUS CANCIONES MÁS ESCUCHADAS'
        : recent
        ? 'TU HISTORIAL'
        : liked
        ? 'LISTA AUTOMÁTICA'
        : ['PLAYLIST', if (_playlistPrivate == true) 'PRIVADA'].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker,
          style: theme.textTheme.labelMedium?.copyWith(
            color: muted,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                _heroTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            // Una playlist, como un álbum de Limusic: descargarla entera y
            // guardarla en la biblioteca (si no es propia). Reproducir y
            // aleatorio quedan en los tres puntos y en las canciones.
            if (widget.surface == MusicSurface.playlist &&
                widget.playlistId != null &&
                widget.connection.nativeCatalog)
              CollectionActions(
                id: widget.playlistId!,
                album: false,
                tracks: tracks,
                title: _heroTitle,
                subtitle: 'Playlist',
                thumbnailUrl: (_mosaic?.isNotEmpty ?? false)
                    ? _mosaic!.first
                    : tracks.firstOrNull?.thumbnailUrl,
                loadAll: _loadAllTracks,
                heart: _ownKnown && !_editable,
              )
            else if (firstPlayable != null &&
                widget.connection.nativeCatalog) ...[
              IconButton(
                tooltip: 'Aleatorio',
                iconSize: 28,
                style: IconButton.styleFrom(fixedSize: const Size.square(52)),
                icon: const Icon(Icons.shuffle_rounded),
                onPressed: () => _play(firstPlayable, shuffled: true),
              ),
              IconButton.filled(
                tooltip: 'Reproducir',
                iconSize: 34,
                style: IconButton.styleFrom(fixedSize: const Size.square(60)),
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () => _play(firstPlayable),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (repeat)
          Text(
            [...details, 'Últimos 30 días'].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          )
        else
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: colors.surfaceContainerHighest,
                child: Icon(Icons.person, size: 16, color: muted),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: widget.connection.account?.name ?? '',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      for (final detail in details)
                        TextSpan(
                          text: ' · $detail',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        if (liked) ...[
          const SizedBox(height: 12),
          Text(
            'La música que marcas con Me gusta en YouTube aparece aquí.',
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  /// Botones flotantes de la playlist: volver a la izquierda y, a la derecha,
  /// una píldora con actualizar y las opciones de cola.
  Widget _playlistControls(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final glass = colors.surfaceContainerHighest.withValues(alpha: .82);
    final hasTracks = _items.whereType<MusicTrack>().any(_canPlayTrack);
    return Row(
      children: [
        // El botón de volver del sistema, con fondo para leerse sobre las
        // portadas.
        BackButton(
          style: IconButton.styleFrom(
            fixedSize: const Size.square(48),
            backgroundColor: glass,
            foregroundColor: colors.onSurface,
          ),
        ),
        const Spacer(),
        Material(
          color: glass,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _refreshPage,
              ),
              // En una playlist o un álbum el menú está siempre: no depende
              // de que las canciones hayan llegado.
              if ((hasTracks ||
                      (widget.playlistId != null &&
                          (widget.surface == MusicSurface.playlist ||
                              widget.surface == MusicSurface.album))) &&
                  widget.connection.nativeCatalog)
                IconButton(
                  tooltip: 'Opciones',
                  icon: const Icon(Icons.more_vert),
                  onPressed: _collectionSheet,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _homeBackdrop() {
    TrackPlaybackController? player;
    try {
      player = ref.read(trackPlaybackControllerProvider);
    } on Object {
      player = null;
    }
    final playback = player;
    return HomeBackdrop(
      player: playback ?? ValueNotifier<int>(0),
      coverUrl: () => playback == null || playback.isBundledTrack
          ? null
          : playback.current?.thumbnailUrl,
      scroll: _scroll,
    );
  }

  /// Filtros de la Biblioteca: una fila de píldoras con icono que se desliza,
  /// como la de Limusic. "Todo" es el resumen con las teselas; las demás
  /// muestran una sola colección.
  Widget _libraryChips() {
    final caps = widget.connection.capabilities;
    final initial = _initialSurface();
    final sections = <(MusicSurface?, String, IconData)>[
      (null, 'Todo', Icons.grid_view_rounded),
      (MusicSurface.playlists, 'Playlists', Icons.queue_music_rounded),
      if (caps.contains('albums'))
        (MusicSurface.albums, 'Álbumes', Icons.album_rounded),
      if (caps.contains('artists'))
        (MusicSurface.artists, 'Artistas', Icons.people_alt_rounded),
      if (caps.contains('songs'))
        (MusicSurface.songs, 'Canciones', Icons.music_note_rounded),
      if (caps.contains('liked'))
        (
          MusicSurface.liked,
          widget.connection.nativeCatalog
              ? 'Me gusta de YouTube Music'
              : 'Me gusta',
          Icons.favorite_rounded,
        ),
      if (caps.contains('channelLiked'))
        (
          MusicSurface.channelLiked,
          'Me gusta de mi canal',
          Icons.favorite_rounded,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (final (key, label, icon) in sections)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  selected: key == null ? _all : !_all && _surface == key,
                  onSelected: (_) {
                    final target = key ?? initial;
                    final same = _surface == target;
                    if (same && _all == (key == null)) return;
                    setState(() {
                      _all = key == null;
                      _surface = target;
                    });
                    if (!same) unawaited(_load(reset: true));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// El año de un texto como `Álbum · 2024`, o null si no trae ninguno.
  static String? _year(String? detail) => detail == null
      ? null
      : RegExp(r'\b(19|20)\d{2}\b').firstMatch(detail)?.group(0);

  /// Filas del contenido. Los artistas consecutivos de una misma sección se
  /// agrupan de tres en tres para formar la cuadrícula de fotos.
  List<Widget> _itemRows(
    BuildContext context,
    bool isHome,
    bool hasShelves,
    MusicTrack? firstPlayable,
  ) {
    final rows = <Widget>[];
    if (_surface == MusicSurface.album && _items.isNotEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 18),
          child: Center(
            child: AlbumDiscArt(
              size: 148,
              url: _items.whereType<MusicTrack>().firstOrNull?.thumbnailUrl,
            ),
          ),
        ),
      );
    }
    var artists = <Widget>[];
    void flushArtists() {
      for (var i = 0; i < artists.length; i += 3) {
        rows.add(
          ArtistPhotoRow(
            tiles: artists.sublist(
              i,
              i + 3 > artists.length ? artists.length : i + 3,
            ),
          ),
        );
      }
      artists = <Widget>[];
    }

    TrackPlaybackController? player;
    try {
      player = ref.read(trackPlaybackControllerProvider);
    } on Object {
      player = null;
    }
    var covers = <Widget>[];
    void flushCovers() {
      for (var i = 0; i < covers.length; i += 3) {
        rows.add(
          ArtistPhotoRow(
            tiles: covers.sublist(
              i,
              i + 3 > covers.length ? covers.length : i + 3,
            ),
          ),
        );
      }
      covers = <Widget>[];
    }

    // El Inicio abre con un collage de acceso rápido, como el de YouTube
    // Music, y debajo los accesos directos a la biblioteca.
    //  - Sin secciones: el collage son las primeras canciones de la lista.
    //  - Con secciones: son las canciones de la primera, que deja de pintarse
    //    como carrusel para no repetirlas.
    final hero = <MusicItem>{};
    final shelfRows = <Widget>[];
    final shelfTracks = <MusicTrack>[];
    Widget? collage;
    if (isHome && _layout.dial) {
      // Con un ambiente elegido el collage son los resultados de su búsqueda;
      // sin él, es el guardado (ver _restoreDial y _settleDial).
      final List<MusicItem> dial;
      if (_mood != null) {
        final firstShelf = _items.isEmpty ? null : _items.first.shelfTitle;
        final found = _items
            .whereType<MusicTrack>()
            .where(
              (t) =>
                  _canPlayTrack(t) &&
                  (!hasShelves || t.shelfTitle == firstShelf),
            )
            .take(_dialSize)
            .toList();
        dial = _wholePages(found);
      } else {
        dial = _dialFrozen ?? const [];
      }
      final dialTracks = dial.whereType<MusicTrack>().toList();
      if (dial.isNotEmpty) {
        // Lo del primer estante que ya está en el collage no se repite más
        // abajo. Las canciones que el collage toma de otros estantes para
        // llenarse se quedan también en el suyo.
        final shown = {for (final t in dialTracks) t.id};
        final first = _items.isEmpty ? null : _items.first.shelfTitle;
        hero.addAll(
          _items.whereType<MusicTrack>().where(
            (t) =>
                shown.contains(t.id) && (!hasShelves || t.shelfTitle == first),
          ),
        );
        collage = Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: SpeedDialGrid(
            onTouch: (index) {
              final touched = dial[index];
              if (touched is MusicTrack) _touchTrack(touched);
            },
            // Cabecera como la de YouTube Music: nombre en versalitas y título.
            eyebrow: _mood == null
                ? widget.connection.account?.name
                : 'Ambiente',
            heading: _mood ?? 'Accesos directos',
            playing: player,
            isActive: player == null
                ? null
                : (index) =>
                      dial[index] is MusicTrack &&
                      player!.current?.id == 'youtube:${dial[index].id}',
            items: [
              for (final item in dial)
                switch (item) {
                  MusicTrack() => (
                    title: item.title,
                    subtitle: item.artist,
                    url: item.thumbnailUrl,
                    onTap: () => _play(item, from: dialTracks),
                    onLongPress: widget.connection.nativeCatalog
                        ? () => _openSheet(item)
                        : null,
                  ),
                  _ => (
                    title: item.title,
                    subtitle: 'Playlist',
                    url: (item as MusicPlaylist).thumbnailUrl,
                    onTap: () => context.push(
                      '/music/playlist/${Uri.encodeComponent(item.id)}',
                      extra: PageSeed(
                        title: item.title,
                        imageUrl: item.thumbnailUrl,
                      ),
                    ),
                    onLongPress: widget.connection.nativeCatalog
                        ? () => _openSheet(item)
                        : null,
                  ),
                },
            ],
          ),
        );
      } else if (_mood == null && _items.isNotEmpty && !_sideReady) {
        // Aún no hay collage guardado ni datos completos: un esqueleto, no un
        // collage provisional que luego se sustituya por otro.
        collage = const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: SkeletonGrid(),
        );
      }
    }
    Widget? shortcuts;
    if (isHome && widget.connection.nativeCatalog) {
      final music = widget.controller;
      // De fábrica, hasta que el usuario fije o quite algo: las colecciones
      // (como el «Liked songs» de Limusic) y detrás las playlists de la cuenta.
      music.defaultShortcuts = [
        ...collectionShortcuts(widget.connection.capabilities).where(
          (shortcut) => const {
            Shortcut.liked,
            Shortcut.artists,
            Shortcut.recents,
          }.contains(shortcut.id),
        ),
        for (final playlist in _shortcutPlaylists)
          Shortcut(
            ShortcutKind.playlist,
            playlist.id,
            playlist.title,
            subtitle: playlist.isPrivate ? 'Playlist · Privada' : 'Playlist',
            thumbnail: playlist.thumbnailUrl,
          ),
      ].take(Shortcut.max).toList();
      final pinned = music.effectiveShortcuts;
      void pick() => unawaited(
        showShortcutPicker(context, music, widget.connection.generation!),
      );
      if (_layout.shortcuts) {
        final theme = Theme.of(context), colors = theme.colorScheme;
        shortcuts = Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OnePeShortcuts(
                onAdd: pinned.length < Shortcut.max ? pick : null,
                items: [
                  for (final shortcut in pinned)
                    (
                      title: shortcut.title,
                      subtitle: shortcut.subtitle ?? '',
                      url: shortcut.thumbnail,
                      icon: shortcutIcon(shortcut),
                      onTap: () => _openShortcut(shortcut),
                      // Mantener pulsado: la hoja de su playlist o su álbum,
                      // con «Quitar de atajos».
                      onLongPress: () => unawaited(
                        showShortcutMenu(
                          context,
                          ref,
                          shortcut,
                          onChanged: () => unawaited(_loadSideData()),
                        ),
                      ),
                    ),
                ],
              ),
              // Sin atajos, una sola fila ancha en vez de teselas fantasma.
              if (pinned.isEmpty)
                Material(
                  color: colors.onSurface.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: pick,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: SizedBox.square(
                              dimension: 40,
                              child: Icon(
                                Icons.add_rounded,
                                size: 22,
                                color: colors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Añadir atajo',
                                  style: theme.textTheme.titleSmall,
                                ),
                                Text(
                                  'Fija aquí tus playlists, álbumes y '
                                  'colecciones',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }
    }
    if (!hasShelves) {
      if (shortcuts != null && _items.isNotEmpty) rows.add(shortcuts);
      if (collage != null) rows.add(collage);
    }

    // Con secciones (Inicio), cada una es un carrusel horizontal de tarjetas.
    var strip = <Widget>[];
    void flushStrip() {
      if (strip.isEmpty) return;
      rows.add(_ShelfStrip(cards: strip));
      strip = <Widget>[];
    }

    var rank = 0;
    final albumGrid =
        widget.surface == MusicSurface.songs && _surface == MusicSurface.albums;
    for (final (index, item) in _items.indexed) {
      final inShelf = hasShelves && item.shelfTitle != null;
      final startsShelf =
          inShelf &&
          (index == 0 || _items[index - 1].shelfTitle != item.shelfTitle);
      if (startsShelf || !inShelf) flushStrip();
      if (startsShelf || item is! MusicArtist) flushArtists();
      if (item is! MusicPlaylist && !(item is MusicAlbum && albumGrid)) {
        flushCovers();
      }
      if (startsShelf && index == 0 && collage == null && shortcuts != null) {
        rows.add(shortcuts);
      }
      if (startsShelf) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
            child: Semantics(
              header: true,
              child: Text(
                item.shelfTitle!,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 20),
              ),
            ),
          ),
        );
      }
      if (startsShelf && index == 0 && collage != null) {
        if (shortcuts != null) rows.add(shortcuts);
        rows.add(collage);
      }
      if (hero.contains(item)) continue;
      if (inShelf) {
        strip.add(_shelfCard(item));
        continue;
      }
      switch (item) {
        case MusicAlbum() when albumGrid:
          // En la Biblioteca los álbumes son una cuadrícula de portadas con su
          // año debajo, como la de Limusic.
          covers.add(
            CoverCard(
              key: ValueKey('album:${item.id}'),
              title: item.title,
              subtitle: _year(item.detail) ?? item.artist ?? 'Álbum',
              url: item.thumbnailUrl,
              fallbackIcon: Icons.album,
              onTap: () => openAlbum(
                context,
                item.id,
                seed: PageSeed(title: item.title, imageUrl: item.thumbnailUrl),
              ),
            ),
          );
        case MusicAlbum():
          rows.add(
            AlbumDiscCard(
              key: ValueKey('album:${item.id}'),
              title: item.title,
              subtitle: [
                item.artist,
                item.detail,
              ].whereType<String>().join(' · ').nullIfEmptyOr('Álbum'),
              url: item.thumbnailUrl,
              onTap: () => openAlbum(
                context,
                item.id,
                seed: PageSeed(title: item.title, imageUrl: item.thumbnailUrl),
              ),
            ),
          );
        case MusicArtist():
          artists.add(
            ArtistPhotoTile(
              key: ValueKey('artist:${item.id}'),
              name: item.title,
              detail: item.detail,
              url: item.thumbnailUrl,
              onTap: () => openArtist(
                context,
                item.id,
                seed: PageSeed(title: item.title, imageUrl: item.thumbnailUrl),
              ),
              onLongPress: () => _openSheet(item),
            ),
          );
        case MusicPlaylist() when widget.surface == MusicSurface.songs:
          // En Biblioteca las playlists van en cuadrícula de portadas.
          covers.add(
            CoverCard(
              key: ValueKey('playlist:${item.id}'),
              title: item.title,
              subtitle: item.isPrivate ? 'Privada' : 'Playlist',
              url: item.thumbnailUrl,
              fallbackIcon: Icons.queue_music,
              onTap: () => context.push(
                '/music/playlist/${Uri.encodeComponent(item.id)}',
                extra: PageSeed(title: item.title, imageUrl: item.thumbnailUrl),
              ),
              onLongPress: widget.connection.nativeCatalog
                  ? () => _openSheet(item)
                  : null,
            ),
          );
        case MusicPlaylist():
          rows.add(
            SongRow(
              key: ValueKey('playlist:${item.id}'),
              url: item.thumbnailUrl,
              fallbackIcon: Icons.queue_music,
              title: item.title,
              subtitle: item.isPrivate ? 'Playlist · Privada' : 'Playlist',
              onLongPress: widget.connection.nativeCatalog
                  ? () => _openSheet(item)
                  : null,
              trailing: widget.connection.nativeCatalog
                  ? null
                  : const Icon(Icons.chevron_right),
              onTap: () => context.push(
                '/music/playlist/${Uri.encodeComponent(item.id)}',
                extra: PageSeed(title: item.title, imageUrl: item.thumbnailUrl),
              ),
            ),
          );
        case MusicTrack() when widget.surface == MusicSurface.onRepeat:
          rank++;
          final top = rank == 1;
          final play = _canPlayTrack(item) ? () => _play(item) : null;
          final hold = widget.connection.nativeCatalog
              ? () => _openSheet(item)
              : null;
          bool current() => player?.current?.id == 'youtube:${item.id}';
          rows.add(
            _warm(
              item,
              top
                  ? TopSongCard(
                      key: ValueKey('top:${item.id}'),
                      title: item.title,
                      artist: item.artist,
                      plays: item.playCount,
                      url: item.thumbnailUrl,
                      onTap: play,
                      onLongPress: hold,
                      playback: player,
                      isCurrent: current,
                    )
                  : RankedSongRow(
                      key: ValueKey('top:$rank:${item.id}'),
                      rank: rank,
                      title: item.title,
                      artist: item.artist,
                      plays: item.playCount,
                      url: item.thumbnailUrl,
                      onTap: play,
                      onLongPress: hold,
                      playback: player,
                      isCurrent: current,
                    ),
            ),
          );
        case MusicTrack():
          // En Inicio las canciones que no caben en el collage van a un
          // estante de cuatro filas que se pasa de lado, no a una lista larga.
          if (isHome && !hasShelves && _canPlayTrack(item)) {
            shelfTracks.add(item);
          }
          (isHome && !hasShelves ? shelfRows : rows).add(
            _warm(
              item,
              SongRow(
                key: ValueKey('track:$index:${item.id}'),
                playback: player,
                isCurrent: () => player?.current?.id == 'youtube:${item.id}',
                isRunning: () => player?.phase == TrackAudioPhase.playing,
                url: item.thumbnailUrl,
                fallbackIcon: _canPlayTrack(item)
                    ? Icons.play_circle_outline
                    : Icons.music_note,
                title: item.title,
                onLongPress: widget.connection.nativeCatalog
                    ? () => _openSheet(item)
                    : null,
                subtitle: [
                  item.artist,
                  if (item.playCount != null) '${item.playCount} escuchas',
                  if (item.listenedAt != null && item.playCount == null)
                    MaterialLocalizations.of(
                      context,
                    ).formatShortDate(item.listenedAt!.toLocal()),
                  if (widget.connection.nativeCatalog &&
                      widget.controller.deviceAudio(item.id) != null)
                    'En este dispositivo'
                  else if (widget.connection.nativeCatalog &&
                      !_canPlayTrack(item))
                    'Solo biblioteca',
                ].join(' · '),
                onTap: _canPlayTrack(item) ? () => _play(item) : null,
              ),
            ),
          );
      }
    }
    flushArtists();
    flushCovers();
    flushStrip();
    if (shelfRows.isNotEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    _mood == null ? 'Sigue escuchando' : 'Más de $_mood',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: 20),
                  ),
                ),
              ),
              // Como el «Play all» de los estantes de canciones de Limusic.
              if (shelfTracks.isNotEmpty)
                TextButton(
                  onPressed: () => _play(shelfTracks.first, from: shelfTracks),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  child: const Text('Reproducir todo'),
                ),
            ],
          ),
        ),
      );
      rows.add(SongGridShelf(rows: shelfRows));
    }
    // Inicio entra en cascada: cada sección aparece un instante después de la
    // anterior (las lejanas, construidas al desplazar, aparecen sin espera).
    if (isHome) {
      return [
        for (final (i, row) in rows.indexed)
          Reveal(
            key: ValueKey('reveal:$i'),
            delay: Duration(milliseconds: 70 * (i < 7 ? i : 0)),
            child: row,
          ),
      ];
    }
    return rows;
  }

  Widget _shelfCard(MusicItem item) {
    void open(String kind) =>
        context.push('/music/$kind/${Uri.encodeComponent(item.id)}');
    return switch (item) {
      MusicArtist() => SizedBox(
        key: ValueKey('artist:${item.id}'),
        width: _ShelfStrip.cover,
        child: Align(
          alignment: Alignment.topCenter,
          child: ArtistPhotoTile(
            name: item.title,
            detail: item.detail,
            url: item.thumbnailUrl,
            onTap: () => openArtist(
              context,
              item.id,
              seed: PageSeed(title: item.title, imageUrl: item.thumbnailUrl),
            ),
            onLongPress: () => _openSheet(item),
          ),
        ),
      ),
      MusicAlbum() => _ShelfCard(
        key: ValueKey('album:${item.id}'),
        title: item.title,
        subtitle: 'Álbum',
        art: AlbumDiscArt(size: _ShelfStrip.cover, url: item.thumbnailUrl),
        onTap: () => openAlbum(
          context,
          item.id,
          seed: PageSeed(title: item.title, imageUrl: item.thumbnailUrl),
        ),
        onLongPress: widget.connection.nativeCatalog
            ? () => _openSheet(item)
            : null,
      ),
      MusicPlaylist() => _ShelfCard(
        key: ValueKey('playlist:${item.id}'),
        title: item.title,
        subtitle: item.isPrivate ? 'Playlist privada' : 'Playlist',
        art: TrackArtwork(
          url: item.thumbnailUrl,
          size: _ShelfStrip.cover,
          borderRadius: 16,
          fallbackIcon: Icons.queue_music,
        ),
        onTap: () => open('playlist'),
        onLongPress: widget.connection.nativeCatalog
            ? () => _openSheet(item)
            : null,
      ),
      MusicTrack() => _warm(
        item,
        _ShelfCard(
          key: ValueKey('track:${item.id}'),
          title: item.title,
          subtitle: item.artist,
          art: TrackArtwork(
            url: item.thumbnailUrl,
            size: _ShelfStrip.cover,
            borderRadius: 16,
            fallbackIcon: _canPlayTrack(item)
                ? Icons.play_circle_outline
                : Icons.music_note,
          ),
          onTap: _canPlayTrack(item) ? () => _play(item) : null,
          onLongPress: widget.connection.nativeCatalog
              ? () => _openSheet(item)
              : null,
        ),
      ),
    };
  }

  Future<void> _loadSideAfterMain() async {
    // Hasta ~15 s de espera a la carga principal; luego se pide igualmente.
    for (var i = 0; i < 30 && mounted && _loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    // Una primera pintura limpia antes de pedir más.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    if (widget.surface == MusicSurface.home) _warmVisible();
    await _loadSideData();
    _settleDial();
  }

  /// Adelanta el audio de las primeras canciones de la pantalla: las del
  /// collage de Inicio, los primeros resultados de una búsqueda o el comienzo
  /// de una playlist. Son las que más se tocan nada más llegar.
  void _warmVisible() {
    final generation = widget.connection.generation;
    // Solo si el motor de audio ya existe: adelantar no justifica crearlo.
    if (generation == null ||
        !widget.controller.isCurrent(generation) ||
        !ref.exists(trackPlaybackControllerProvider)) {
      return;
    }
    ref
        .read(trackPlaybackControllerProvider)
        .warmTracks(
          _items
              .whereType<MusicTrack>()
              .where(_canPlayTrack)
              .take(TrackPlaybackController.warmLimit)
              .map(
                (track) => widget.controller.playbackTrack(generation, track),
              ),
        );
  }

  /// Playlists para los accesos del Inicio y la foto del primer artista que se
  /// sigue para la tesela de la Biblioteca. Un fallo deja el acceso sin portada.
  Future<void> _loadSideData() async {
    final generation = widget.connection.generation;
    if (generation == null) return;
    final caps = widget.connection.capabilities;
    Future<MusicPage?> fetch(MusicSurface surface) async {
      try {
        final page = await widget.controller.page(
          generation,
          surface,
          quiet: true,
        );
        return mounted && widget.controller.isCurrent(generation) ? page : null;
      } on Object {
        return null;
      }
    }

    // Lo más escuchado y lo último que sonó alimentan el collage de Inicio.
    if (widget.surface == MusicSurface.home) {
      final played = caps.contains('onRepeat')
          ? await fetch(MusicSurface.onRepeat)
          : null;
      final recent = caps.contains('mysicRecents')
          ? await fetch(MusicSurface.mysicRecents)
          : null;
      if (mounted && (played != null || recent != null)) {
        setState(() {
          _played =
              played?.items.whereType<MusicTrack>().take(_dialSize).toList() ??
              _played;
          _recentTracks =
              recent?.items.whereType<MusicTrack>().take(_dialSize).toList() ??
              _recentTracks;
        });
      }
    }
    if (widget.surface == MusicSurface.home && caps.contains('playlists')) {
      final page = await fetch(MusicSurface.playlists);
      if (page != null && mounted) {
        setState(() {
          // Nueve: una por cada tercera casilla de las 27 del collage.
          _shortcutPlaylists = page.items
              .whereType<MusicPlaylist>()
              .take(9)
              .toList();
        });
      }
    }
    if (widget.surface == MusicSurface.songs) {
      // Portada de la primera pista, artista, álbum o playlist de la colección.
      String? coverOf(MusicPage? page) => page?.items
          .map(
            (item) => switch (item) {
              MusicTrack() => item.thumbnailUrl,
              MusicArtist() => item.thumbnailUrl,
              MusicAlbum() => item.thumbnailUrl,
              MusicPlaylist() => item.thumbnailUrl,
            },
          )
          .whereType<String>()
          .firstOrNull;

      final collections = <String, MusicSurface>{
        if (caps.contains('liked'))
          'liked': MusicSurface.liked
        else if (caps.contains('channelLiked'))
          'liked': MusicSurface.channelLiked,
        if (caps.contains('artists')) 'artists': MusicSurface.artists,
        if (caps.contains('mysicRecents'))
          'history': MusicSurface.mysicRecents
        else if (caps.contains('history'))
          'history': MusicSurface.history,
        if (caps.contains('onRepeat')) 'repeat': MusicSurface.onRepeat,
      };
      // En paralelo: cada pastilla aparece con su portada en cuanto llega.
      await Future.wait([
        for (final entry in collections.entries)
          fetch(entry.value).then((page) {
            final cover = coverOf(page);
            if (cover != null && mounted) {
              setState(() => _tileCovers[entry.key] = cover);
            }
          }),
      ]);
    }
  }

  void _homeChanged() {
    if (mounted) setState(() {});
  }

  HomeLayout get _layout => widget.controller.homeLayout.value;

  void _openShortcut(Shortcut shortcut) {
    switch (shortcut.kind) {
      case ShortcutKind.collection:
        context.push(switch (shortcut.id) {
          Shortcut.liked => '/music/liked',
          Shortcut.downloads => '/downloads',
          Shortcut.mostPlayed => '/music/repeat',
          Shortcut.artists => '/music/artists',
          _ => '/history',
        });
      case ShortcutKind.playlist:
        context.push(
          '/music/playlist/${Uri.encodeComponent(shortcut.id)}',
          extra: PageSeed(title: shortcut.title, imageUrl: shortcut.thumbnail),
        );
      case ShortcutKind.album:
        openAlbum(
          context,
          shortcut.id,
          seed: PageSeed(title: shortcut.title, imageUrl: shortcut.thumbnail),
        );
      case ShortcutKind.track:
        // Una canción fijada suena con su radio detrás.
        final track = trackOfShortcut(shortcut);
        if (_canPlayTrack(track)) _play(track, from: [track]);
    }
  }

  @override
  void dispose() {
    if (widget.surface == MusicSurface.home) {
      widget.controller.shortcuts.removeListener(_homeChanged);
      widget.controller.homeLayout.removeListener(_homeChanged);
    }
    _scroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _request?.cancel();
    _search.dispose();
    super.dispose();
  }
}

/// Barra de la playlist: invisible sobre el mosaico y opaca, con el título,
/// en cuanto la cabecera ha pasado. Opaca y no desenfocada: va sobre una
/// lista larga y así no cuesta nada al desplazar.
class _PlaylistBar extends StatelessWidget {
  const _PlaylistBar({
    required this.scroll,
    required this.start,
    required this.title,
  });

  final ScrollController scroll;
  final double start;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paper = theme.colorScheme.surface;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: scroll,
        builder: (context, _) {
          final offset = scroll.hasClients ? scroll.offset : 0.0;
          final shown = ((offset - start) / 48).clamp(0.0, 1.0).toDouble();
          if (shown == 0) return const SizedBox.shrink();
          return ColoredBox(
            color: paper.withValues(alpha: shown),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                72,
                MediaQuery.paddingOf(context).top,
                124,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: shown),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Fondo de la barra superior. Es transparente arriba del todo y, al
/// desplazar, solo baja un velo del color de la página que se desvanece hacia
/// abajo: la barra sigue fija pero nunca es un bloque, y no cuesta nada de
/// dibujar (antes desenfocaba lo que pasaba por debajo en cada fotograma).
class _BarBlur extends StatelessWidget {
  const _BarBlur({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final paper = Theme.of(context).colorScheme.surface;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: scroll,
        builder: (context, _) {
          final shown = ((scroll.hasClients ? scroll.offset : 0.0) / 32)
              .clamp(0.0, 1.0)
              .toDouble();
          if (shown == 0) return const SizedBox.shrink();
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  // Opaca tras el título y la barra de estado: lo que sube
                  // por debajo no se lee a través de ellos.
                  paper.withValues(alpha: shown),
                  paper.withValues(alpha: shown),
                  paper.withValues(alpha: 0),
                ],
                stops: const [0, .82, 1],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lista perezosa: solo construye las filas visibles (y un margen), de modo
/// que una biblioteca de cientos de canciones no infla todos sus widgets ni
/// descarga todas sus portadas al abrir la pantalla.
class _LazyColumn extends StatelessWidget {
  const _LazyColumn({
    required this.padding,
    required this.children,
    this.controller,
  });

  final EdgeInsets padding;
  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: controller,
    padding: padding,
    // Siempre desplazable: así también se puede tirar para actualizar una
    // lista corta.
    physics: const AlwaysScrollableScrollPhysics(),
    // Una pantalla de margen: las filas que están por entrar ya existen y
    // tienen su portada pedida, así que el desplazamiento no muestra huecos.
    scrollCacheExtent: const ScrollCacheExtent.viewport(1),
    itemCount: children.length,
    itemBuilder: (context, index) => children[index],
  );
}

/// Carrusel horizontal de una sección del Inicio. Perezoso también en
/// horizontal: solo existen las tarjetas que caben en pantalla.
class _ShelfStrip extends StatelessWidget {
  const _ShelfStrip({required this.cards});

  static const cover = 132.0;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: cover + 14 + MediaQuery.textScalerOf(context).scale(46),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      // Las tarjetas se deslizan por debajo del margen de la página en vez
      // de cortarse en seco a 16 px del borde.
      clipBehavior: Clip.none,
      itemCount: cards.length,
      separatorBuilder: (context, index) => const SizedBox(width: 12),
      itemBuilder: (context, index) => cards[index],
    ),
  );
}

class _ShelfCard extends StatelessWidget {
  const _ShelfCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.art,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final Widget art;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressScale(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            art,
            const SizedBox(height: 8),
            SizedBox(
              width: _ShelfStrip.cover,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _OrDefault on String {
  String nullIfEmptyOr(String fallback) => isEmpty ? fallback : this;
}
