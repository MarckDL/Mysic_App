import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/app_settings.dart';
import '../../authentication/presentation/account_screen.dart'
    show AccountAction;
import '../../playback/application/playback_providers.dart';
import '../../playback/application/track_playback_controller.dart';
import '../../playback/domain/track_audio_engine.dart' show TrackAudioPhase;
import '../../search/presentation/catalog_widgets.dart' show TrackArtwork;
import '../../search/presentation/music_tiles.dart';
import '../application/music_mode_controller.dart';
import '../domain/music_mode.dart';
import '../domain/music_search.dart';
import 'catalog_pages.dart';
import 'cover_art.dart';
import 'library_screen.dart'
    show LibraryChip, LibraryCoverTile, LibrarySectionHeader;
import 'mood_screen.dart';
import 'tab_top_bar.dart';
import 'track_sheet.dart';

/// Sube cada vez que se vuelve a tocar la pestaña Buscar estando en ella: la
/// pantalla empieza una búsqueda nueva (campo vacío, con foco y teclado).
final searchTabReselected = ValueNotifier<int>(0);

/// Lo que enseña la pestaña: con el campo vacío, recientes y géneros; mientras
/// se escribe, sugerencias; tras buscar, resultados (Limusic `SearchUIType`).
enum _Mode { browse, suggestions, results }

/// La pestaña Buscar, con la estructura de `SearchScreen.kt` de Limusic: bajo
/// la cabecera de las pestañas, el campo en forma de píldora y, con
/// resultados, los chips de tipo; el contenido cambia con un fundido.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    required this.controller,
    required this.connection,
  });

  final MusicModeController controller;
  final MusicConnection connection;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _fieldHeight = 56.0;
  static const _chipsHeight = 46.0;

  /// Los tipos cuya lista completa es su propia búsqueda filtrada.
  static const _cardKinds = {
    SearchKind.albums,
    SearchKind.artists,
    SearchKind.playlists,
  };

  static const _kindLabels = {
    SearchKind.all: 'Todo',
    SearchKind.songs: 'Canciones',
    SearchKind.videos: 'Vídeos',
    SearchKind.albums: 'Álbumes',
    SearchKind.artists: 'Artistas',
    SearchKind.playlists: 'Playlists',
  };

  static const _hints = [
    'Buscar canciones…',
    'Buscar artistas…',
    'Buscar álbumes…',
    'Buscar playlists…',
    'Buscar vídeos…',
  ];

  final _text = TextEditingController();
  final _focus = FocusNode();
  final _resultsScroll = ScrollController();

  /// El panel de sugerencias está abierto (hay foco y aún no se ha buscado).
  var _expanded = false;

  /// El texto lo está cambiando el código, no el usuario.
  var _quiet = false;

  var _kind = SearchKind.all;
  SearchResults? _results;
  var _query = '';
  var _searchingAll = false;
  var _searchingKind = false;
  var _failed = false;
  final _loaded = <SearchKind>{};
  CancelToken? _request;
  CancelToken? _kindRequest;
  Future<void>? _searching;

  var _suggestions = const SearchSuggestions();
  Timer? _suggestTimer;
  CancelToken? _suggestRequest;

  List<MoodSection>? _moods;
  var _moodsFailed = false;
  final _art = <String, String>{};
  final _artAsked = <String>{};

  var _hint = 0;
  Timer? _hintTimer;

  String? get _generation => widget.connection.generation;
  bool get _loading => _searchingAll || _searchingKind;

  _Mode get _mode => _text.text.isEmpty
      ? _Mode.browse
      : _expanded
      ? _Mode.suggestions
      : _Mode.results;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
    _focus.addListener(_onFocus);
    searchTabReselected.addListener(_startOver);
    // El texto de ayuda rota cada 3 s mientras no se escribe.
    _hintTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && !_focus.hasFocus && _text.text.isEmpty) {
        setState(() => _hint = (_hint + 1) % _hints.length);
      }
    });
    unawaited(
      widget.controller.restoreSearches().then((_) {
        if (mounted) setState(() {});
      }),
    );
    unawaited(_loadMoods());
  }

  @override
  void dispose() {
    searchTabReselected.removeListener(_startOver);
    _hintTimer?.cancel();
    _suggestTimer?.cancel();
    _request?.cancel();
    _kindRequest?.cancel();
    _suggestRequest?.cancel();
    _text.dispose();
    _focus.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  // ---- Campo ----

  void _onFocus() {
    if (!mounted) return;
    setState(() {
      if (_focus.hasFocus) _expanded = true;
    });
  }

  void _onText() {
    if (_quiet || !mounted) return;
    setState(() {
      if (_focus.hasFocus) _expanded = true;
      if (_text.text.isEmpty) _suggestions = const SearchSuggestions();
    });
    if (_focus.hasFocus) _suggest();
  }

  void _setText(String value) {
    _quiet = true;
    _text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _quiet = false;
  }

  /// Cierra el panel de sugerencias (la flecha del campo y el botón Atrás).
  void _dismiss() {
    _focus.unfocus();
    setState(() => _expanded = false);
  }

  /// Volver a tocar la pestaña: búsqueda nueva. La anterior queda a un toque
  /// en las recientes.
  void _startOver() {
    if (!mounted) return;
    _setText('');
    setState(() {
      _expanded = true;
      _suggestions = const SearchSuggestions();
    });
    _focus.requestFocus();
  }

  void _suggest() {
    _suggestTimer?.cancel();
    final input = _text.text.trim();
    final generation = _generation;
    if (input.isEmpty || generation == null) return;
    // Un respiro entre teclas: una petición por pausa, no por letra.
    _suggestTimer = Timer(const Duration(milliseconds: 120), () async {
      _suggestRequest?.cancel();
      final request = _suggestRequest = CancelToken();
      try {
        final found = await widget.controller.ask(
          generation,
          (client) => client.suggest(input, cancelToken: request),
        );
        if (mounted && request == _suggestRequest) {
          setState(() => _suggestions = found);
        }
      } on Object {
        // Sin sugerencias se sigue pudiendo buscar.
      }
    });
  }

  // ---- Búsqueda ----

  void _runSearch(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    _setText(query);
    _focus.unfocus();
    widget.controller.rememberSearch(query);
    setState(() => _expanded = false);
    _searching = _search(query);
    _toTop();
  }

  void _toTop() {
    if (_resultsScroll.hasClients) _resultsScroll.jumpTo(0);
  }

  /// La búsqueda de Limusic: tres peticiones a la vez (general, canciones y
  /// vídeos). Los demás chips piden su lista al abrirse.
  Future<void> _search(String query) async {
    final generation = _generation;
    if (generation == null) return;
    _request?.cancel();
    _kindRequest?.cancel();
    final request = _request = CancelToken();
    setState(() {
      _query = query;
      _searchingAll = true;
      _searchingKind = false;
      _failed = false;
      _loaded.clear();
    });
    try {
      final found = await widget.controller.ask(
        generation,
        (client) => client.searchAll(query, cancelToken: request),
      );
      if (!mounted || request != _request) return;
      setState(() {
        _results = found;
        _searchingAll = false;
      });
      // La búsqueda abre el chip que esté elegido cuando llega.
      if (_cardKinds.contains(_kind)) await _loadKind(_kind);
    } on Object {
      if (mounted && request == _request && !request.isCancelled) {
        setState(() {
          _searchingAll = false;
          _failed = true;
        });
      }
    }
  }

  void _setKind(SearchKind kind) {
    if (kind == _kind) return;
    _kindRequest?.cancel();
    setState(() {
      _kind = kind;
      _searchingKind = false;
      if (!_searchingAll) _failed = false;
    });
    _toTop();
    if (_searchingAll || _results == null || _query.isEmpty) return;
    if (_cardKinds.contains(kind) && !_loaded.contains(kind)) {
      unawaited(_loadKind(kind));
    }
  }

  Future<void> _loadKind(SearchKind kind) async {
    final generation = _generation;
    if (generation == null) return;
    _kindRequest?.cancel();
    final request = _kindRequest = CancelToken();
    final query = _query;
    setState(() {
      _searchingKind = true;
      _failed = false;
    });
    try {
      final items = await widget.controller.ask(
        generation,
        (client) => client.searchKind(query, kind, cancelToken: request),
      );
      if (!mounted || request != _kindRequest) return;
      setState(() {
        _results = _results?.withKind(kind, items);
        _loaded.add(kind);
        _searchingKind = false;
      });
    } on Object {
      if (mounted && request == _kindRequest && !request.isCancelled) {
        setState(() {
          _searchingKind = false;
          // Lo que la búsqueda general ya trajo de este tipo sigue sirviendo.
          _failed = !(_results?.has(kind) ?? false);
        });
      }
    }
  }

  // ---- Géneros y ambientes ----

  Future<void> _loadMoods() async {
    final generation = _generation;
    if (generation == null) return;
    final music = widget.controller;
    try {
      final saved = await music.ask(
        generation,
        (client) => client.rememberedMoods(),
      );
      if (saved != null && mounted && _moods == null) {
        setState(() => _moods = saved);
      }
    } on Object {
      // Sin copia guardada se espera a la red.
    }
    try {
      final fresh = await music.ask(generation, (client) => client.moods());
      if (!mounted) return;
      if (fresh.isNotEmpty) {
        setState(() => _moods = fresh);
      } else if (_moods == null) {
        setState(() => _moodsFailed = true);
      }
    } on Object {
      if (mounted && _moods == null) setState(() => _moodsFailed = true);
    }
  }

  /// La portada de una categoría se pide cuando su tesela entra en pantalla.
  void _wantArt(String params) {
    final generation = _generation;
    if (generation == null || !_artAsked.add(params)) return;
    unawaited(() async {
      try {
        final url = await widget.controller.ask(
          generation,
          (client) => client.moodArtwork(params),
        );
        if (url != null && mounted) setState(() => _art[params] = url);
      } on Object {
        // La tesela se ve terminada sin portada.
      }
    }());
  }

  void _openMood(MoodItem item, String section) => context.push(
    '/music/mood',
    extra: MoodSeed(
      params: item.params,
      title: item.title,
      color: item.color,
      artwork: _art[item.params],
      kicker: section,
    ),
  );

  // ---- Reproducción y navegación ----

  TrackPlaybackController get _player =>
      ref.read(trackPlaybackControllerProvider);

  TrackPlaybackController? get _playerIfAny =>
      ref.exists(trackPlaybackControllerProvider) ? _player : null;

  bool _canPlay(MusicTrack track) =>
      canPlayMusicTrack(widget.controller, track);

  /// Un resultado suena como siempre en Limusic: la canción y luego su radio.
  void _playOne(MusicTrack track) => _playAll([track]);

  void _playAll(List<MusicTrack> tracks) {
    final generation = _generation;
    final music = widget.controller;
    final playable = tracks.where(_canPlay).toList();
    if (generation == null ||
        !music.isCurrent(generation) ||
        playable.isEmpty) {
      return;
    }
    unawaited(
      _player.playQueue([
        for (final track in playable.take(TrackPlaybackController.maxQueue))
          music.playbackTrack(generation, track),
      ], listenForTrack: () => music.listenForTrack(generation)),
    );
    context.push('/player');
  }

  /// El botón de reproducir del resultado principal: la canción con su radio,
  /// el álbum entero o las canciones destacadas del artista.
  Future<void> _playTop(MusicItem top) async {
    final music = widget.controller;
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (top) {
        case MusicTrack():
          _playOne(top);
        case MusicAlbum():
          final album = await music.albumDetail(top.id);
          if (mounted) _playAll(album.tracks);
        case MusicArtist():
          final artist = await music.artistProfile(top.id);
          if (mounted) _playAll(artist.topSongs);
        case MusicPlaylist():
          _open(top);
      }
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo reproducir.')),
      );
    }
  }

  static String? _coverOf(MusicItem item) => switch (item) {
    MusicTrack() => item.thumbnailUrl,
    MusicArtist() => item.thumbnailUrl,
    MusicAlbum() => item.thumbnailUrl,
    MusicPlaylist() => item.thumbnailUrl,
  };

  void _open(MusicItem item) {
    final seed = PageSeed(title: item.title, imageUrl: _coverOf(item));
    switch (item) {
      case MusicPlaylist():
        context.push(
          '/music/playlist/${Uri.encodeComponent(item.id)}',
          extra: seed,
        );
      case MusicAlbum():
        openAlbum(context, item.id, seed: seed);
      case MusicArtist():
        openArtist(context, item.id, seed: seed);
      case MusicTrack():
        if (_canPlay(item)) _playOne(item);
    }
  }

  /// Mantener pulsado: la hoja de opciones del elemento.
  void _hold(MusicItem item) => unawaited(showItemMenu(context, ref, item));

  void _warm(MusicTrack track, {required bool touch}) {
    final generation = _generation;
    final player = _playerIfAny;
    if (!mounted ||
        player == null ||
        generation == null ||
        !_canPlay(track) ||
        !widget.controller.isCurrent(generation)) {
      return;
    }
    final playable = widget.controller.playbackTrack(generation, track);
    touch ? player.touchTrack(playable) : player.warmTracks([playable]);
  }

  /// Fila de canción: adelanta su audio al detenerse en ella y al tocarla.
  Widget _songRow(MusicTrack track, {required String key}) {
    final player = _playerIfAny;
    return TouchWarm(
      key: ValueKey('$key:${track.id}'),
      onTouch: () => _warm(track, touch: true),
      onLinger: () => _warm(track, touch: false),
      child: SongRow(
        playback: player,
        isCurrent: () => player?.current?.id == 'youtube:${track.id}',
        isRunning: () => player?.phase == TrackAudioPhase.playing,
        url: track.thumbnailUrl,
        title: track.title,
        subtitle: track.artist,
        onTap: _canPlay(track) ? () => _playOne(track) : null,
        onLongPress: () => _hold(track),
      ),
    );
  }

  // ---- Interfaz ----

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    final barHeight =
        MediaQuery.paddingOf(context).top +
        TabTopBar.height +
        _fieldHeight +
        10 +
        (mode == _Mode.results ? _chipsHeight : 0);
    return PopScope(
      // Atrás cierra primero el panel de sugerencias.
      canPop: mode != _Mode.suggestions,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Scaffold(
        body: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              child: KeyedSubtree(
                key: ValueKey(mode),
                child: switch (mode) {
                  _Mode.browse => _browse(context, barHeight),
                  _Mode.suggestions => _suggestionList(context, barHeight),
                  _Mode.results => _resultsView(context, barHeight),
                },
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              // Los toques en los huecos de la barra no llegan a lo de debajo.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: TabTopBar(
                  title: 'Buscar',
                  actions: const [AccountAction()],
                  bottom: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _field(context, mode),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: mode == _Mode.results
                            ? _chips()
                            : const SizedBox(width: double.infinity),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// La píldora de búsqueda (Limusic: `SearchBar` de forma circular sobre el
  /// color de las tarjetas): lupa que se vuelve flecha con el panel abierto,
  /// texto de ayuda que rota y aspa cuando hay texto.
  Widget _field(BuildContext context, _Mode mode) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final panel = mode == _Mode.suggestions;
    return Material(
      color: colors.surfaceContainerHigh,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: _fieldHeight,
        child: Row(
          children: [
            SizedBox.square(
              dimension: 48,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: panel
                    ? IconButton(
                        key: const ValueKey('back'),
                        tooltip: 'Atrás',
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                        ),
                        onPressed: _dismiss,
                      )
                    : Icon(
                        Icons.search,
                        key: const ValueKey('search'),
                        color: colors.onSurfaceVariant,
                      ),
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  if (_text.text.isEmpty)
                    IgnorePointer(
                      child: ClipRect(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [...previous, ?current],
                          ),
                          // El nuevo sube desde abajo; el anterior sale por
                          // arriba.
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: child.key == ValueKey(_hint)
                                        ? const Offset(0, 1)
                                        : const Offset(0, -1),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Text(
                            _hints[_hint],
                            key: ValueKey(_hint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  TextField(
                    controller: _text,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    inputFormatters: [LengthLimitingTextInputFormatter(120)],
                    style: theme.textTheme.bodyLarge,
                    // Sin el borde ni el relleno que el tema da a los campos: la
                    // píldora ya es el campo.
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onSubmitted: _runSearch,
                  ),
                ],
              ),
            ),
            if (_text.text.isNotEmpty)
              IconButton(
                tooltip: 'Borrar',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _setText('');
                  setState(() => _suggestions = const SearchSuggestions());
                },
              )
            else
              const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  Widget _chips() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: SearchKind.values.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final kind = SearchKind.values[index];
          return LibraryChip(
            label: _kindLabels[kind]!,
            selected: kind == _kind,
            onTap: () => _setKind(kind),
          );
        },
      ),
    ),
  );

  double get _bottom => 24 + MediaQuery.paddingOf(context).bottom;

  // -- Campo vacío: recientes y géneros --

  Widget _browse(BuildContext context, double top) {
    final recent = widget.controller.recentSearches;
    final moods = _moods;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: top)),
        if (recent.isNotEmpty)
          SliverToBoxAdapter(
            child: _RecentSearches(
              queries: recent,
              onSearch: _runSearch,
              onForget: (query) =>
                  setState(() => widget.controller.forgetSearch(query)),
              onClear: () => setState(widget.controller.forgetSearch),
            ),
          ),
        if (moods == null && !_moodsFailed)
          const SliverToBoxAdapter(
            child: SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (moods == null)
          // Sin las categorías de YouTube Music, los géneros de siempre: cada
          // uno es una búsqueda.
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LibrarySectionHeader(
                  title: 'Géneros y ambientes',
                  padding: EdgeInsets.only(top: 8, bottom: 6),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GenreGrid(onPick: (label, query) => _runSearch(query)),
                ),
              ],
            ),
          )
        else
          for (final (index, section) in moods.indexed)
            ..._moodSection(section, _moodKind(index, moods.length)),
        SliverToBoxAdapter(child: SizedBox(height: _bottom)),
      ],
    );
  }

  /// Qué sección es cuál, por posición como Limusic: YouTube termina con
  /// «Ambientes y momentos» y luego «Géneros»; lo anterior es «Para ti».
  static _MoodKind _moodKind(int index, int count) => index == count - 1
      ? _MoodKind.genres
      : index == count - 2
      ? _MoodKind.moods
      : _MoodKind.forYou;

  List<Widget> _moodSection(MoodSection section, _MoodKind kind) => [
    if (section.title.isNotEmpty)
      SliverToBoxAdapter(
        child: LibrarySectionHeader(
          title: section.title,
          padding: const EdgeInsets.only(top: 8, bottom: 4),
        ),
      ),
    if (kind == _MoodKind.forYou)
      SliverToBoxAdapter(
        child: SizedBox(
          height: 136,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: section.items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = section.items[index];
              // Solo se construyen las teselas a la vista: pedir aquí la
              // portada es lo que la hace perezosa.
              _wantArt(item.params);
              return SizedBox(
                width: 300,
                child: _MoodTile(
                  key: ValueKey('${section.title}/${item.params}'),
                  kind: kind,
                  title: item.title,
                  color: Color(item.color),
                  artwork: _art[item.params],
                  onTap: () => _openMood(item, section.title),
                ),
              );
            },
          ),
        ),
      )
    else
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: kind == _MoodKind.moods ? 112 : 100,
          ),
          itemCount: section.items.length,
          itemBuilder: (context, index) {
            final item = section.items[index];
            _wantArt(item.params);
            return _MoodTile(
              key: ValueKey('${section.title}/${item.params}'),
              kind: kind,
              title: item.title,
              color: Color(item.color),
              artwork: _art[item.params],
              onTap: () => _openMood(item, section.title),
            );
          },
        ),
      ),
    const SliverToBoxAdapter(child: SizedBox(height: 12)),
  ];

  // -- Mientras se escribe: sugerencias --

  Widget _suggestionList(BuildContext context, double top) {
    final theme = Theme.of(context);
    final items = _suggestions.items;
    final queries = _suggestions.queries;
    return ListView.builder(
      padding: EdgeInsets.only(top: top, bottom: _bottom, left: 16, right: 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: items.length + queries.length,
      itemBuilder: (context, index) {
        if (index < items.length) {
          final item = items[index];
          return _SuggestedItem(
            key: ValueKey('item:${item.id}'),
            item: item,
            url: _coverOf(item),
            onTap: () {
              _focus.unfocus();
              _open(item);
            },
            onLongPress: () => _hold(item),
          );
        }
        final query = queries[index - items.length];
        return InkWell(
          key: ValueKey('query:$query'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => _runSearch(query),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                // Lleva la sugerencia al campo para seguir escribiendo.
                IconButton(
                  tooltip: 'Completar',
                  icon: const Icon(Icons.north_west_rounded),
                  onPressed: () {
                    _text.value = TextEditingValue(
                      text: query,
                      selection: TextSelection.collapsed(offset: query.length),
                    );
                    _focus.requestFocus();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -- Tras buscar: resultados --

  Widget _resultsView(BuildContext context, double top) {
    final theme = Theme.of(context);
    final results = _results;
    final Widget child;
    if (_loading) {
      // Diez filas de esqueleto, con el mismo margen que los resultados.
      child = ListView(
        key: const ValueKey('loading'),
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: top, left: 16, right: 16),
        children: const [SkeletonRows(count: 10)],
      );
    } else if (_failed) {
      child = _Centered(
        key: const ValueKey('error'),
        top: top,
        children: [
          Text(
            'Ocurrió un error',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () {
              if (_text.text.trim().isNotEmpty) _runSearch(_text.text);
            },
            child: const Text('Reintentar'),
          ),
        ],
      );
    } else if (results == null || !results.has(_kind)) {
      child = _Centered(
        key: const ValueKey('empty'),
        top: top,
        children: [
          Text(
            'No se encontraron resultados',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ],
      );
    } else {
      child = CustomScrollView(
        key: const ValueKey('results'),
        controller: _resultsScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: top)),
          ..._resultSlivers(context, results),
          SliverToBoxAdapter(child: SizedBox(height: _bottom)),
        ],
      );
    }
    return RefreshIndicator(
      edgeOffset: top,
      onRefresh: () {
        _runSearch(_text.text);
        return _searching ?? Future.value();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: child,
      ),
    );
  }

  List<Widget> _resultSlivers(BuildContext context, SearchResults results) {
    Widget box(Widget child) => SliverToBoxAdapter(child: child);

    Widget header(String title, SearchKind more) => box(
      LibrarySectionHeader(
        title: title,
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        onMore: () => _setKind(more),
      ),
    );

    Widget rows(List<MusicTrack> tracks, String key) => SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: tracks.length,
        itemBuilder: (context, index) => _songRow(tracks[index], key: key),
      ),
    );

    final scale = MediaQuery.textScalerOf(context);

    // Un estante que se pasa de lado, con 6 dp de margen: las tarjetas traen
    // sus 10 dp, así la carátula queda a 16 dp como los títulos.
    Widget shelf<T extends MusicItem>(
      List<T> items,
      double width,
      double height,
      Widget Function(T item) card,
    ) => box(
      SizedBox(
        height: height,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          itemCount: items.length,
          itemBuilder: (context, index) =>
              SizedBox(width: width, child: card(items[index])),
        ),
      ),
    );

    Widget cover(MusicItem item, String subtitle, IconData icon) =>
        LibraryCoverTile(
          key: ValueKey('${item.runtimeType}:${item.id}'),
          title: item.title,
          subtitle: subtitle,
          url: _coverOf(item),
          icon: icon,
          onTap: () => _open(item),
          onLongPress: () => _hold(item),
        );

    Widget albumCard(MusicAlbum album) =>
        cover(album, album.detail ?? 'Álbum', Icons.album);
    Widget playlistCard(MusicPlaylist playlist) =>
        cover(playlist, 'Playlist', Icons.queue_music);
    Widget artistCard(MusicArtist artist) => _ArtistCircle(
      key: ValueKey('artist:${artist.id}'),
      artist: artist,
      onTap: () => _open(artist),
      onLongPress: () => _hold(artist),
    );

    // Una cuadrícula de tarjetas, con el alto que piden su carátula y su texto.
    // Con [columns] null, las mismas columnas que la cuadrícula de álbumes y
    // playlists de la Biblioteca (`LibraryGridCells`): las que dejan la
    // portada cerca de 150 dp, nunca menos de tres.
    Widget grid<T extends MusicItem>(
      List<T> items,
      int? columns,
      double Function(double cell) extent,
      Widget Function(T item) card,
    ) => SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      sliver: SliverLayoutBuilder(
        builder: (context, box) {
          final count =
              columns ??
              ((box.crossAxisExtent + 12) / 170).round().clamp(3, 12);
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              mainAxisExtent: extent(box.crossAxisExtent / count),
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => card(items[index]),
          );
        },
      ),
    );

    double coverExtent(double cell) => (cell - 20) + 16 + scale.scale(58);
    double artistExtent(double cell) => (cell - 20) + 28 + scale.scale(40);

    switch (_kind) {
      case SearchKind.songs:
        return [rows(results.songs, 'songs')];
      case SearchKind.videos:
        return [rows(results.videos, 'videos')];
      case SearchKind.albums:
        return [grid(results.albums, null, coverExtent, albumCard)];
      case SearchKind.playlists:
        return [grid(results.playlists, null, coverExtent, playlistCard)];
      case SearchKind.artists:
        return [grid(results.artists, 3, artistExtent, artistCard)];
      case SearchKind.all:
        final top = results.top;
        final songs = results.songs.take(5).toList();
        return [
          if (top != null)
            box(
              _TopResultCard(
                item: top,
                subtitle: results.topSubtitle,
                url: _coverOf(top),
                onTap: () => _open(top),
                onLongPress: () => _hold(top),
                onPlay: () => unawaited(_playTop(top)),
                songs: [
                  for (final track in results.topSongs)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _songRow(track, key: 'top'),
                    ),
                ],
              ),
            ),
          if (songs.isNotEmpty) ...[
            header('Canciones', SearchKind.songs),
            rows(songs, 'all'),
          ],
          if (results.albums.isNotEmpty) ...[
            header('Álbumes', SearchKind.albums),
            shelf(results.albums, 140, coverExtent(140), albumCard),
          ],
          if (results.artists.isNotEmpty) ...[
            header('Artistas', SearchKind.artists),
            shelf(results.artists, 136, artistExtent(136), artistCard),
          ],
          if (results.videos.isNotEmpty) ...[
            header('Vídeos', SearchKind.videos),
            shelf(
              results.videos,
              240,
              220 * 9 / 16 + 28 + scale.scale(58),
              (video) => _VideoCard(
                key: ValueKey('video:${video.id}'),
                video: video,
                onTap: _canPlay(video) ? () => _playOne(video) : null,
                onLongPress: () => _hold(video),
              ),
            ),
          ],
          if (results.playlists.isNotEmpty) ...[
            header('Playlists', SearchKind.playlists),
            shelf(results.playlists, 140, coverExtent(140), playlistCard),
          ],
        ];
    }
  }
}

/// Las tres familias de teselas de «Ambientes y géneros».
enum _MoodKind { forYou, moods, genres }

/// Las búsquedas recientes (Limusic `RecentSearches`): una fila que se pasa de
/// lado, la más nueva primero, cada una con su aspa para olvidarla.
class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    required this.queries,
    required this.onSearch,
    required this.onForget,
    required this.onClear,
  });

  final List<String> queries;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onForget;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibrarySectionHeader(
          title: 'Búsquedas recientes',
          trailing: InkWell(
            onTap: onClear,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                'Borrar',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: queries.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final query = queries[index];
              return Material(
                key: ValueKey(query),
                color: colors.onSurface.withValues(alpha: .06),
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => onSearch(query),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 14, right: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search,
                              size: 15,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Text(
                                query,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colors.onSurface.withValues(
                                    alpha: .85,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Semantics(
                        button: true,
                        label: 'Olvidar $query',
                        child: InkWell(
                          onTap: () => onForget(query),
                          customBorder: const CircleBorder(),
                          child: SizedBox.square(
                            dimension: 28,
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Lo que se ve de [child] conserva la opacidad de un degradado horizontal que
/// va de transparente a opaco en [stop] (el `mask-image` de Limusic).
Widget _fadeIn(Widget child, double stop) => ShaderMask(
  blendMode: BlendMode.dstIn,
  shaderCallback: (rect) => LinearGradient(
    colors: const [Colors.transparent, Colors.black],
    stops: [0, stop],
  ).createShader(rect),
  child: child,
);

/// Tesela de «Ambientes y géneros» (Limusic `MoodCategoryCard.kt`): el nombre
/// arriba a la izquierda, el color de YouTube para la categoría mezclado con
/// el de las tarjetas y su portada a la derecha, colocada distinto en cada
/// sección. [artwork] es null hasta resolverse; la tesela se ve terminada sin
/// ella.
class _MoodTile extends StatelessWidget {
  const _MoodTile({
    super.key,
    required this.kind,
    required this.title,
    required this.color,
    required this.onTap,
    this.artwork,
  });

  final _MoodKind kind;
  final String title;
  final Color color;
  final String? artwork;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final tint = Color.lerp(colors.surfaceContainerHigh, color, .14)!;
    final art = artwork == null ? null : CoverArt(artwork!, pixels: 360);

    Widget name(double size) {
      final style = theme.textTheme.titleLarge?.copyWith(
        fontSize: size,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
      );
      // Una sola palabra larga («Concentración») se encoge para caber en vez
      // de partirse por la mitad.
      return title.trim().contains(' ')
          ? Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            )
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: Text(title, maxLines: 1, softWrap: false, style: style),
            );
    }

    final children = switch (kind) {
      // Para ti: la portada como un panel a la derecha que se funde con la
      // tarjeta, y la marca de la app.
      _MoodKind.forYou => [
        if (art != null)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 174,
            child: _fadeIn(art, .7),
          ),
        Positioned(top: 16, left: 18, width: 156, child: name(20)),
        Positioned(
          left: 18,
          bottom: 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surface.withValues(alpha: .7),
              border: Border.all(color: color.withValues(alpha: .5)),
            ),
            child: SizedBox.square(
              dimension: 30,
              child: Icon(
                Icons.graphic_eq_rounded,
                size: 18,
                color: colors.primary,
              ),
            ),
          ),
        ),
      ],
      // Ambientes: la portada como un disco medio fuera por la derecha, y una
      // pastilla del color.
      _MoodKind.moods => [
        Positioned(
          right: -26,
          top: 4,
          child: _fadeIn(
            SizedBox.square(
              dimension: 104,
              child: ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: color.withValues(alpha: .45)),
                    ?art,
                    // El agujero del disco, del color de la tesela.
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.onSurface.withValues(alpha: .12),
                        ),
                        child: SizedBox.square(
                          dimension: 22,
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: tint,
                              ),
                              child: const SizedBox.square(dimension: 16),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            .6,
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 0, 16),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: .6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  name(17),
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: color,
                      shape: const StadiumBorder(),
                    ),
                    child: const SizedBox(width: 28, height: 5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      // Géneros: una funda inclinada en la esquina, con el color brillando
      // detrás, y un punto.
      _MoodKind.genres => [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.bottomRight,
                radius: .95,
                colors: [color.withValues(alpha: .5), Colors.transparent],
                stops: const [0, .75],
              ),
            ),
          ),
        ),
        Positioned(
          right: -8,
          bottom: -20,
          child: Transform.rotate(
            angle: 16 * math.pi / 180,
            child: _fadeIn(
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 84,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: color.withValues(alpha: .45)),
                      ?art,
                    ],
                  ),
                ),
              ),
              .55,
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, top: 14),
            child: FractionallySizedBox(
              alignment: Alignment.topLeft,
              widthFactor: .62,
              heightFactor: 1,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En la primera línea: un nombre de dos líneas cuelga bajo
                  // sí mismo, no bajo el punto.
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                      child: const SizedBox.square(dimension: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: name(15.5)),
                ],
              ),
            ),
          ),
        ),
      ],
    };

    // El marco de la familia: tarjeta teñida, borde fino y un leve hundido al
    // pulsar.
    return PressScale(
      child: Material(
        color: tint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.onSurface.withValues(alpha: .07)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            button: true,
            label: title,
            child: Stack(fit: StackFit.expand, children: children),
          ),
        ),
      ),
    );
  }
}

/// Un elemento que YouTube Music propone mientras se escribe (Limusic
/// `SuggestItemRow`): miniatura de 40 dp (redonda si es un artista), título y
/// una línea.
class _SuggestedItem extends StatelessWidget {
  const _SuggestedItem({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.url,
  });

  final MusicItem item;
  final String? url;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = this.item;
    final subtitle = switch (item) {
      MusicTrack() => item.artist,
      MusicAlbum() => item.detail ?? 'Álbum',
      MusicArtist() => 'Artista',
      MusicPlaylist() => 'Playlist',
    };
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            TrackArtwork(
              url: url,
              size: 40,
              borderRadius: item is MusicArtist ? 20 : 4,
              fallbackIcon: switch (item) {
                MusicTrack() => Icons.music_note,
                MusicAlbum() => Icons.album,
                MusicArtist() => Icons.person,
                MusicPlaylist() => Icons.queue_music,
              },
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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

/// El resultado principal (Limusic `TopResultCard`): la respuesta, no una
/// tarjeta entre muchas. Iluminada por su propia carátula, con la portada
/// grande, el título a tamaño de cabecera, un botón de reproducir que hace lo
/// propio de cada tipo y las canciones que YouTube le empareja.
class _TopResultCard extends StatelessWidget {
  const _TopResultCard({
    required this.item,
    required this.subtitle,
    required this.onTap,
    required this.onLongPress,
    required this.onPlay,
    required this.songs,
    this.url,
  });

  final MusicItem item;
  final String subtitle;
  final String? url;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onPlay;
  final List<Widget> songs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final card = colors.surfaceContainerHigh;
    final round = item is MusicArtist;
    final long = item.title.length > 28;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Material(
        color: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.onSurface.withValues(alpha: .07)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Su carátula, desenfocada hasta no reconocerse, fundiéndose con
            // la tarjeta. Sin desenfoque, la tarjeta lisa es el diseño.
            if (url != null && !EffectsScope.reducedOf(context)) ...[
              Positioned.fill(
                child: Opacity(
                  opacity: .6,
                  child: Transform.scale(
                    scale: 1.25,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: 40,
                        sigmaY: 40,
                        tileMode: TileMode.clamp,
                      ),
                      child: CoverArt(url!, pixels: 96),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        card.withValues(alpha: .3),
                        card.withValues(alpha: .75),
                        card,
                      ],
                      stops: const [0, .5, 1],
                    ),
                  ),
                ),
              ),
            ],
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            shape: round ? BoxShape.circle : BoxShape.rectangle,
                            borderRadius: round
                                ? null
                                : BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x55000000),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TrackArtwork(
                            url: url,
                            size: 96,
                            borderRadius: round ? 48 : 12,
                            fallbackIcon: switch (item) {
                              MusicArtist() => Icons.person,
                              MusicAlbum() => Icons.album,
                              _ => Icons.music_note,
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontSize: long ? 19 : 24,
                                  height: long ? 22 / 19 : 27 / 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (subtitle.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: colors.primary,
                          shape: const CircleBorder(),
                          elevation: 6,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onPlay,
                            child: Tooltip(
                              message: 'Reproducir',
                              child: SizedBox.square(
                                dimension: 48,
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: colors.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (songs.isNotEmpty) ...[
                  Divider(
                    height: 1,
                    color: colors.onSurface.withValues(alpha: .08),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(children: songs),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Un artista como foto redonda sobre su nombre (Limusic `ArtistCircle`).
class _ArtistCircle extends StatelessWidget {
  const _ArtistCircle({
    super.key,
    required this.artist,
    required this.onTap,
    required this.onLongPress,
  });

  final MusicArtist artist;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    onLongPress: onLongPress,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, box) => Column(
          children: [
            TrackArtwork(
              url: artist.thumbnailUrl,
              size: box.maxWidth,
              borderRadius: box.maxWidth / 2,
              fallbackIcon: Icons.person,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                artist.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Un vídeo musical con su forma, 16:9, para que la fila de Vídeos se lea
/// distinta de las de canciones (Limusic `VideoCard`).
class _VideoCard extends StatelessWidget {
  const _VideoCard({
    super.key,
    required this.video,
    required this.onTap,
    required this.onLongPress,
  });

  final MusicTrack video;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: colors.surfaceContainerHigh,
                  // La miniatura de YouTube es 4:3 con franjas negras; el
                  // recorte las quita.
                  child: video.thumbnailUrl == null
                      ? Icon(
                          Icons.music_video_rounded,
                          color: colors.onSurfaceVariant,
                        )
                      : CoverArt(video.thumbnailUrl!, pixels: 360),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
            Text(
              video.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un estado sin lista (error, sin resultados): centrado, y desplazable para
/// poder tirar y actualizar.
class _Centered extends StatelessWidget {
  const _Centered({super.key, required this.top, required this.children});

  final double top;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: box.maxHeight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, top, 32, 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    ),
  );
}
