import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/network/api_failure.dart';

typedef _Json = Map<String, dynamic>;

_Json _obj(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};
List<Object?> _list(Object? value) => value is List ? value : const [];
String _str(Object? value) => value is String ? value : '';

_Json _at(Object? value, List<String> keys) {
  var node = _obj(value);
  for (final key in keys) {
    node = _obj(node[key]);
  }
  return node;
}

String _label(Object? value) {
  final data = _obj(value);
  final simple = _str(data['simpleText']);
  if (simple.isNotEmpty) return simple;
  return _list(data['runs']).map((run) => _str(_obj(run)['text'])).join();
}

_Json _browse(_Json endpoint) => _obj(endpoint['browseEndpoint']);

String _pageType(_Json endpoint) => _str(
  _at(_browse(endpoint), [
    'browseEndpointContextSupportedConfigs',
    'browseEndpointContextMusicConfig',
  ])['pageType'],
);

final _videoId = RegExp(r'^[\w-]{11}$');
final _resourceId = RegExp(r'^[\w-]{1,150}$');
final _artistId = RegExp(r'^UC[\w-]{22}$');

/// Una página de la biblioteca o del Inicio de YouTube Music ya leída, con
/// la misma forma JSON que entrega el servidor (ver `MusicPage.fromJson`).
class YtmPage {
  YtmPage();

  final items = <Map<String, dynamic>>[];
  String? next;
  String? title;
  int excluded = 0;

  /// La playlist es de la cuenta: se puede editar, vaciar y eliminar.
  bool editable = false;

  Map<String, dynamic> toJson() => {
    'items': items,
    'nextCursor': next,
    'excludedCount': excluded,
    if (title != null) 'title': title,
    if (editable) 'editable': true,
  };
}

_Json? _card(_Json value, String surface) {
  final columns = _list(value['flexColumns'])
      .map(
        (col) =>
            _at(col, ['musicResponsiveListItemFlexColumnRenderer', 'text']),
      )
      .toList();
  final titleText = value['title'] ?? (columns.isEmpty ? null : columns[0]);
  final title = _label(titleText).trim();
  if (title.isEmpty ||
      _str(value['musicItemRendererDisplayPolicy']).contains('GREY_OUT')) {
    return null;
  }
  final runs = _list(_obj(titleText)['runs']);
  final titleEndpoint = runs.isEmpty
      ? const <String, dynamic>{}
      : _obj(_obj(runs.first)['navigationEndpoint']);
  final root = _obj(value['navigationEndpoint']);
  final thumb = _at(value['thumbnail'] ?? value['thumbnailRenderer'], [
    'musicThumbnailRenderer',
    'thumbnail',
  ]);
  final urls = _list(
    thumb['thumbnails'],
  ).map((t) => _str(_obj(t)['url'])).where((u) => u.startsWith('https://'));
  final thumbnailUrl = urls.isEmpty ? null : urls.last;
  final endpoint = root['browseEndpoint'] != null ? root : titleEndpoint;
  // En la búsqueda la segunda línea empieza por el tipo ("Álbum • Artista •
  // 2020", "Artista • 1,2 M de oyentes"): se guarda sin él.
  String? searchDetail() {
    if (!_isSearch(surface)) return null;
    final parts = _label(columns.length > 1 ? columns[1] : value['subtitle'])
        .split(RegExp(r'\s[•·]\s'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length > 1) parts.removeAt(0);
    return parts.isEmpty ? null : parts.join(' • ');
  }

  final type = _pageType(endpoint);
  final id = _str(_browse(endpoint)['browseId']);
  if (type.contains('PODCAST') || type.contains('NON_MUSIC')) return null;
  if (id.isNotEmpty && _resourceId.hasMatch(id)) {
    if ((type == 'MUSIC_PAGE_TYPE_ALBUM' ||
            (type.isEmpty && surface == 'albums')) &&
        RegExp(r'^(?:MPLA)?MPRE').hasMatch(id)) {
      return {
        'kind': 'album',
        'id': id.replaceFirst(RegExp(r'^MPLA'), ''),
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'subtitle': ?searchDetail(),
      };
    }
    // Los estantes envían el id de la playlist o su identificador VL.
    final playlistId = id.replaceFirst(RegExp(r'^VL'), '');
    if (playlistId.isNotEmpty &&
        ((type == 'MUSIC_PAGE_TYPE_PLAYLIST' &&
                (id.startsWith('VL') ||
                    RegExp(r'^(?:PL|RD|OLAK5uy_)[\w-]+$').hasMatch(id))) ||
            (type.isEmpty && surface == 'playlists' && id.startsWith('VL')))) {
      return {
        'kind': 'playlist',
        'id': playlistId,
        'title': title,
        'private': false,
        'thumbnailUrl': thumbnailUrl,
      };
    }
    if (type == 'MUSIC_PAGE_TYPE_ARTIST' && _artistId.hasMatch(id)) {
      return {
        'kind': 'artist',
        'id': id,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'subtitle': ?searchDetail(),
      };
    }
    return null;
  }
  final overlay = _at(value['overlay'] ?? value['thumbnailOverlay'], [
    'musicItemThumbnailOverlayRenderer',
    'content',
    'musicPlayButtonRenderer',
    'playNavigationEndpoint',
  ]);
  final endpoints = [titleEndpoint, root, overlay];
  if (endpoints.any((e) => e['reelWatchEndpoint'] != null)) return null;
  final watch = endpoints.map((e) => _obj(e['watchEndpoint'])).toList();
  var trackId = _str(_obj(value['playlistItemData'])['videoId']);
  if (trackId.isEmpty) {
    trackId = watch
        .map((w) => _str(w['videoId']))
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
  }
  if (!_videoId.hasMatch(trackId)) return null;
  final kinds = watch
      .where((w) => w['videoId'] == null || w['videoId'] == trackId)
      .map(
        (w) => _str(
          _at(w, [
            'watchEndpointMusicSupportedConfigs',
            'watchEndpointMusicConfig',
          ])['musicVideoType'],
        ),
      )
      .where((s) => s.isNotEmpty)
      .toList();
  final detailRuns = [
    ...columns.skip(1),
    _obj(value['subtitle']),
  ].expand((column) => _list(column['runs'])).map(_obj).toList();
  _Json? albumRun;
  for (final run in detailRuns) {
    if (_pageType(_obj(run['navigationEndpoint'])) == 'MUSIC_PAGE_TYPE_ALBUM') {
      albumRun = run;
      break;
    }
  }
  final albumId = albumRun == null
      ? ''
      : _str(_browse(_obj(albumRun['navigationEndpoint']))['browseId']);
  // Canciones de estudio (ATV), videos musicales (OMV) y subidas de usuarios
  // (UGC); sin tipo, solo las que pertenecen a un álbum.
  if (!(kinds.isNotEmpty || albumRun != null || surface == 'album')) {
    return null;
  }
  final artists = detailRuns
      .where(
        (run) => _artistId.hasMatch(
          _str(_browse(_obj(run['navigationEndpoint']))['browseId']),
        ),
      )
      .toList();
  final durationRe = RegExp(r'^\d{1,3}(?::\d{2}){1,2}$');
  final durationText = [
    ..._list(value['fixedColumns']).map(
      (c) => _label(
        _at(c, ['musicResponsiveListItemFixedColumnRenderer', 'text']),
      ),
    ),
    ...detailRuns.map((r) => _str(r['text'])),
  ].firstWhere(durationRe.hasMatch, orElse: () => '');
  var artist = artists
      .map((r) => _str(r['text']))
      .where((s) => s.isNotEmpty)
      .join(', ');
  if (artist.isEmpty && columns.length > 1) {
    final parts = _label(columns[1]).split(RegExp(r'\s[•·]\s'));
    // En la búsqueda general lo primero es el tipo, no el artista; y las
    // canciones emparejadas con un artista solo traen tipo y duración.
    artist = surface == _searchSurface
        ? parts
              .skip(1)
              .map((part) => part.trim())
              .firstWhere(
                (part) => part.isNotEmpty && !durationRe.hasMatch(part),
                orElse: () => '',
              )
        : parts.first;
  }
  final entryId = _str(_obj(value['playlistItemData'])['playlistSetVideoId']);
  final albumName = albumRun == null ? '' : _str(albumRun['text']);
  return {
    'kind': 'track',
    'id': trackId,
    'title': title,
    'artist': artist,
    if (artists.isNotEmpty)
      'artistId': _str(
        _browse(_obj(artists.first['navigationEndpoint']))['browseId'],
      ),
    if (albumId.isNotEmpty)
      'albumId': albumId.replaceFirst(RegExp(r'^MPLA'), ''),
    if (albumName.isNotEmpty) 'albumName': albumName,
    'thumbnailUrl': thumbnailUrl,
    'durationSeconds': durationText.isEmpty
        ? 0
        : durationText.split(':').fold<int>(0, (n, s) => n * 60 + int.parse(s)),
    'playback': 'native',
    if (entryId.isNotEmpty) 'entryId': entryId,
    // Vídeo musical o subida de un usuario, no la pista de estudio: la
    // búsqueda los separa en su propio estante.
    if (_isSearch(surface) &&
        kinds.isNotEmpty &&
        !kinds.contains('MUSIC_VIDEO_TYPE_ATV'))
      'video': true,
  };
}

/// Superficies con las que se leen las filas de la búsqueda: la general, cuya
/// segunda línea empieza por el tipo ("Canción • Artista • 3:45"), y la
/// filtrada, que no lo lleva en canciones y vídeos.
const _searchSurface = 'searchAll';
const _searchListSurface = 'searchList';

bool _isSearch(String surface) =>
    surface == _searchSurface || surface == _searchListSurface;

const _only = {
  'songs': 'track',
  'liked': 'track',
  'playlist': 'track',
  'album': 'track',
  'search': 'track',
  'artist': 'track',
  'playlists': 'playlist',
  'albums': 'album',
  'artists': 'artist',
};

const _descend = {
  'contents',
  'content',
  'items',
  'sectionListRenderer',
  'singleColumnBrowseResultsRenderer',
  'twoColumnBrowseResultsRenderer',
  'tabbedSearchResultsRenderer',
  'secondaryContents',
  'gridRenderer',
  'musicShelfRenderer',
  'musicShelfContinuation',
  'gridContinuation',
  'musicPlaylistShelfRenderer',
  'musicPlaylistShelfContinuation',
  'sectionListContinuation',
  'musicCarouselShelfRenderer',
  'onResponseReceivedActions',
  'onResponseReceivedCommands',
  'appendContinuationItemsAction',
  'reloadContinuationItemsCommand',
  'continuationItems',
  'continuationContents',
  'header',
  'musicEditablePlaylistDetailHeaderRenderer',
};

/// Si la respuesta indica que no hay sesión iniciada.
bool ytmLoggedOut(Object? raw) {
  final ctx = _obj(_obj(raw)['responseContext']);
  if (_at(ctx, ['mainAppWebResponseContext'])['loggedOut'] == true) return true;
  return _list(ctx['serviceTrackingParams']).any(
    (group) => _list(
      _obj(group)['params'],
    ).any((p) => _obj(p)['key'] == 'logged_in' && _obj(p)['value'] == '0'),
  );
}

/// Convierte la respuesta de `browse` (o su continuación) de la superficie
/// [surface] en elementos musicales.
YtmPage parseYtmPage(Object? raw, String surface, {bool continuation = false}) {
  if (ytmLoggedOut(raw)) {
    throw const ApiFailure(
      'Inicia sesión de nuevo en YouTube Music.',
      code: 'MUSIC_ACCESS_DENIED',
    );
  }
  final page = YtmPage();
  final detail = surface == 'playlist' || surface == 'album';
  var primary = false;

  void visit(Object? value, [String? shelfTitle]) {
    if (value is List) {
      for (final item in value) {
        visit(item, shelfTitle);
      }
      return;
    }
    final node = _obj(value);
    for (final entry in node.entries) {
      final key = entry.key;
      final child = entry.value;
      final r = _obj(child);
      if (key == 'tabRenderer') {
        if (r['selected'] != false) visit(r['content'], shelfTitle);
        continue;
      }
      if (key == 'tabs') {
        final tabs = _list(child);
        final selected = tabs
            .where((t) => _at(t, ['tabRenderer'])['selected'] == true)
            .toList();
        visit(
          selected.isNotEmpty ? selected : tabs.take(1).toList(),
          shelfTitle,
        );
        continue;
      }
      if (const {
            'musicResponsiveHeaderRenderer',
            'musicDetailHeaderRenderer',
            'musicImmersiveHeaderRenderer',
          }.contains(key) ||
          (surface == 'mood' && key == 'musicHeaderRenderer')) {
        page.title ??= _label(r['title']);
        continue;
      }
      if (key == 'musicEditablePlaylistDetailHeaderRenderer') {
        page.editable = true;
        visit(r['header']);
        continue;
      }
      if (key == 'musicCarouselShelfRenderer' ||
          (surface == 'home' && key == 'musicShelfRenderer')) {
        // Las continuaciones de un estante son locales a él; solo el feed
        // exterior hace avanzar el Inicio.
        if (!detail) {
          final heading = surface == 'home' || surface == 'mood'
              ? _label(
                  _at(r, [
                        'header',
                        'musicCarouselShelfBasicHeaderRenderer',
                      ])['title'] ??
                      r['title'],
                ).trim()
              : '';
          visit(
            _list(r['contents'])
                .where((i) => _obj(i)['continuationItemRenderer'] == null)
                .toList(),
            heading.isEmpty ? shelfTitle : heading,
          );
        }
        continue;
      }
      if (surface == 'playlist' &&
          (key == 'musicShelfRenderer' || key == 'musicShelfContinuation')) {
        continue;
      }
      // Las secciones de un ambiente o género ("Playlists destacadas") son
      // cuadrículas con su propio título.
      if (surface == 'mood' && key == 'gridRenderer') {
        primary = true;
        final heading = _label(
          _at(r, ['header', 'gridHeaderRenderer'])['title'],
        ).trim();
        visit(r['items'], heading.isEmpty ? shelfTitle : heading);
        continue;
      }
      if (key == 'musicResponsiveListItemRenderer' ||
          key == 'musicTwoRowItemRenderer') {
        final item = _card(r, surface);
        final kind = _only[surface];
        if (item != null &&
            (kind == null || item['kind'] == kind) &&
            !(surface == 'playlists' &&
                (item['id'] == 'LM' || item['id'] == 'SE'))) {
          page.items.add(
            shelfTitle != null && shelfTitle.isNotEmpty
                ? {...item, 'shelfTitle': shelfTitle}
                : item,
          );
        } else {
          page.excluded++;
        }
        continue;
      }
      if (key == 'continuationItemRenderer') {
        final token = _str(
          _at(r, ['continuationEndpoint', 'continuationCommand'])['token'],
        );
        if (page.next == null && token.isNotEmpty) page.next = token;
        continue;
      }
      if (key == 'continuations') {
        for (final v in _list(child)) {
          final token = _str(_at(v, ['nextContinuationData'])['continuation']);
          final radio = _str(
            _at(v, ['nextRadioContinuationData'])['continuation'],
          );
          final found = token.isNotEmpty ? token : radio;
          if (page.next == null && found.isNotEmpty) page.next = found;
        }
        continue;
      }
      if (_descend.contains(key)) {
        primary = true;
        visit(child, shelfTitle);
      }
    }
  }

  visit(raw);
  // Una continuación sin contenido es el final de la lista, no un error.
  if (!primary && continuation) return page;
  if (!primary) {
    // Solo los nombres de las claves, nunca su contenido.
    debugPrint(
      'ytm_unreadable surface=$surface keys=${_obj(raw).keys.toList()} '
      'contents=${_obj(_obj(raw)['continuationContents']).keys.toList()}',
    );
    throw const ApiFailure(
      'YouTube Music devolvió un formato que Mysic no puede leer.',
      code: 'MUSIC_CATALOG_RESPONSE',
    );
  }
  return page;
}

/// Canciones de la radio de una canción (`next` con la lista `RDAMVM<id>`) y el
/// token para pedir más. Las canciones tienen la forma JSON de
/// `MusicTrack.fromJson`.
class YtmRadioPage {
  YtmRadioPage(this.tracks, this.next);

  final List<Map<String, dynamic>> tracks;
  final String? next;
}

/// Lee la respuesta de `next`: cada `playlistPanelVideoRenderer` es una
/// canción de la cola que YouTube Music propone. Lo que no es una canción de
/// estudio o de vídeo musical (sin id válido, bloqueada) se descarta.
YtmRadioPage parseYtmRadio(Object? raw) {
  if (ytmLoggedOut(raw)) {
    throw const ApiFailure(
      'Inicia sesión de nuevo en YouTube Music.',
      code: 'MUSIC_ACCESS_DENIED',
    );
  }
  final tracks = <Map<String, dynamic>>[];
  final seen = <String>{};
  String? next;

  Map<String, dynamic>? track(_Json r) {
    final id = _str(r['videoId']);
    if (!_videoId.hasMatch(id) || !seen.add(id)) return null;
    final title = _label(r['title']).trim();
    if (title.isEmpty) return null;
    final runs = _list(_obj(r['longBylineText'])['runs']).map(_obj).toList();
    final artists = runs
        .where(
          (run) => _artistId.hasMatch(
            _str(_browse(_obj(run['navigationEndpoint']))['browseId']),
          ),
        )
        .toList();
    _Json? albumRun;
    for (final run in runs) {
      if (_pageType(_obj(run['navigationEndpoint'])) ==
          'MUSIC_PAGE_TYPE_ALBUM') {
        albumRun = run;
        break;
      }
    }
    final albumId = albumRun == null
        ? ''
        : _str(_browse(_obj(albumRun['navigationEndpoint']))['browseId']);
    var artist = artists
        .map((run) => _str(run['text']))
        .where((s) => s.isNotEmpty)
        .join(', ');
    if (artist.isEmpty && runs.isNotEmpty) artist = _str(runs.first['text']);
    final urls = _list(
      _obj(r['thumbnail'])['thumbnails'],
    ).map((t) => _str(_obj(t)['url'])).where((u) => u.startsWith('https://'));
    final lengthText = _label(r['lengthText']).trim();
    final seconds = RegExp(r'^\d{1,3}(?::\d{2}){1,2}$').hasMatch(lengthText)
        ? lengthText.split(':').fold<int>(0, (n, s) => n * 60 + int.parse(s))
        : 0;
    final albumName = albumRun == null ? '' : _str(albumRun['text']);
    return {
      'kind': 'track',
      'id': id,
      'title': title,
      'artist': artist.isEmpty ? 'YouTube Music' : artist,
      if (artists.isNotEmpty)
        'artistId': _str(
          _browse(_obj(artists.first['navigationEndpoint']))['browseId'],
        ),
      if (albumId.isNotEmpty)
        'albumId': albumId.replaceFirst(RegExp(r'^MPLA'), ''),
      if (albumName.isNotEmpty) 'albumName': albumName,
      'thumbnailUrl': urls.isEmpty ? null : urls.last,
      'durationSeconds': seconds,
      'playback': 'native',
    };
  }

  void visit(Object? value) {
    if (value is List) {
      for (final item in value) {
        visit(item);
      }
      return;
    }
    final node = _obj(value);
    for (final entry in node.entries) {
      final r = _obj(entry.value);
      switch (entry.key) {
        case 'playlistPanelVideoRenderer':
          final item = track(r);
          if (item != null) tracks.add(item);
        case 'continuations':
          for (final v in _list(entry.value)) {
            final found = _str(
              _at(v, ['nextRadioContinuationData'])['continuation'],
            );
            final plain = _str(
              _at(v, ['nextContinuationData'])['continuation'],
            );
            final token = found.isNotEmpty ? found : plain;
            if (next == null && token.isNotEmpty) next = token;
          }
        default:
          if (entry.value is Map || entry.value is List) visit(entry.value);
      }
    }
  }

  visit(raw);
  return YtmRadioPage(tracks, next);
}

/// Una respuesta de `search` ya leída. Sin filtro trae el resultado principal
/// ([top], con su línea y las canciones que YouTube le empareja) y filas de
/// todos los tipos en [items]; con filtro, solo [items] de ese tipo. Los
/// elementos tienen la forma JSON de `MusicItem.fromJson`.
class YtmSearchPage {
  Map<String, dynamic>? top;
  String topSubtitle = '';
  final topSongs = <Map<String, dynamic>>[];
  final items = <Map<String, dynamic>>[];
}

void _requireSession(Object? raw) {
  if (ytmLoggedOut(raw)) {
    throw const ApiFailure(
      'Inicia sesión de nuevo en YouTube Music.',
      code: 'MUSIC_ACCESS_DENIED',
    );
  }
}

/// Lee la respuesta de `search`: la tarjeta del resultado principal
/// (`musicCardShelfRenderer`) y, esté en el contenedor que esté (estante de
/// filas, carrusel), cada fila o tarjeta de resultado. [filtered] indica que
/// la búsqueda llevaba filtro de tipo.
YtmSearchPage parseYtmSearch(Object? raw, {bool filtered = false}) {
  _requireSession(raw);
  final page = YtmSearchPage();
  final surface = filtered ? _searchListSurface : _searchSurface;
  // Para diagnosticar un cambio de formato: qué contenedores llegaron y
  // cuántas filas no se entendieron. Solo nombres y recuentos.
  final containers = <String>{};
  var skipped = 0;

  void visit(Object? value, List<Map<String, dynamic>> out) {
    if (value is List) {
      for (final item in value) {
        visit(item, out);
      }
      return;
    }
    for (final entry in _obj(value).entries) {
      final r = _obj(entry.value);
      switch (entry.key) {
        case 'musicCardShelfRenderer':
          containers.add(entry.key);
          if (page.top == null) {
            page.top = _card(r, surface);
            page.topSubtitle = _label(r['subtitle']).trim();
            final paired = <Map<String, dynamic>>[];
            visit(r['contents'], paired);
            // Las canciones de un artista no repiten su nombre: se pone.
            final owner = page.top?['kind'] == 'artist'
                ? _str(page.top?['title'])
                : '';
            page.topSongs.addAll(
              paired
                  .where((item) => item['kind'] == 'track')
                  .take(3)
                  .map(
                    (item) => _str(item['artist']).isEmpty && owner.isNotEmpty
                        ? {...item, 'artist': owner}
                        : item,
                  ),
            );
          }
        case 'musicResponsiveListItemRenderer' || 'musicTwoRowItemRenderer':
          final item = _card(r, surface);
          if (item != null) {
            out.add(item);
          } else {
            skipped++;
          }
        default:
          if (entry.key.endsWith('ShelfRenderer') ||
              entry.key.endsWith('ShelfContinuation')) {
            containers.add(entry.key);
          }
          if (entry.value is Map || entry.value is List) {
            visit(entry.value, out);
          }
      }
    }
  }

  visit(raw, page.items);
  debugPrint(
    'ytm_search filtered=$filtered containers=${containers.toList()} '
    'top=${page.top?['kind']} items=${page.items.length} skipped=$skipped',
  );
  return page;
}

/// Lo que YouTube Music propone mientras se escribe: consultas y, a veces,
/// elementos directos (una canción, un artista…).
class YtmSuggestions {
  final queries = <String>[];
  final items = <Map<String, dynamic>>[];
}

YtmSuggestions parseYtmSuggestions(Object? raw) {
  final page = YtmSuggestions();

  void visit(Object? value) {
    if (value is List) {
      for (final item in value) {
        visit(item);
      }
      return;
    }
    for (final entry in _obj(value).entries) {
      final r = _obj(entry.value);
      switch (entry.key) {
        case 'searchSuggestionRenderer':
          final text = _label(r['suggestion']).trim();
          if (text.isNotEmpty && !page.queries.contains(text)) {
            page.queries.add(text);
          }
        case 'musicResponsiveListItemRenderer':
          final item = _card(r, _searchSurface);
          if (item != null) page.items.add(item);
        default:
          if (entry.value is Map || entry.value is List) visit(entry.value);
      }
    }
  }

  visit(raw);
  return page;
}

/// Las secciones de «Ambientes y géneros» (`FEmusic_moods_and_genres`), en el
/// orden de YouTube: cada una con su título y sus botones (`title`, `params`
/// para abrirlo y `color`, el ARGB de su franja).
List<Map<String, dynamic>> parseYtmMoods(Object? raw) {
  _requireSession(raw);
  final sections = <Map<String, dynamic>>[];

  void section(String title, Object? buttons) {
    final items = <Map<String, dynamic>>[];
    for (final button in _list(buttons)) {
      final b = _obj(_obj(button)['musicNavigationButtonRenderer']);
      final label = _label(b['buttonText']).trim();
      final params = _str(_at(b, ['clickCommand', 'browseEndpoint'])['params']);
      if (label.isEmpty || params.isEmpty) continue;
      final color = _obj(b['solid'])['leftStripeColor'];
      items.add({
        'title': label,
        'params': params,
        'color': color is num ? color.toInt() & 0xFFFFFFFF : 0,
      });
    }
    if (items.isNotEmpty) sections.add({'title': title, 'items': items});
  }

  void visit(Object? value) {
    if (value is List) {
      for (final item in value) {
        visit(item);
      }
      return;
    }
    for (final entry in _obj(value).entries) {
      final r = _obj(entry.value);
      switch (entry.key) {
        case 'gridRenderer':
          section(
            _label(_at(r, ['header', 'gridHeaderRenderer'])['title']).trim(),
            r['items'],
          );
        case 'musicCarouselShelfRenderer':
          section(
            _label(
              _at(r, [
                'header',
                'musicCarouselShelfBasicHeaderRenderer',
              ])['title'],
            ).trim(),
            r['contents'],
          );
        default:
          if (entry.value is Map || entry.value is List) visit(entry.value);
      }
    }
  }

  visit(raw);
  return sections;
}

/// Lo que hace falta para guardar un álbum en la biblioteca: la playlist de
/// audio con que YouTube Music lo guarda (`OLAK5uy_…`) y si ya está guardado.
class YtmAlbumLibrary {
  const YtmAlbumLibrary(this.playlistId, this.saved);

  final String? playlistId;
  final bool saved;
}

/// Lee de la página de un álbum (`browse` de `MPREb_…`) su botón de guardar:
/// un `toggleButtonRenderer` cuyo `defaultServiceEndpoint` es un
/// `likeEndpoint` sobre la playlist de audio; `isToggled` dice si ya está en
/// la biblioteca. Sin ese botón, la playlist sale del enlace canónico.
YtmAlbumLibrary parseYtmAlbumLibrary(Object? raw) {
  _requireSession(raw);
  String? playlistId;
  bool? saved;

  String? likeTarget(Object? endpoint) {
    final like = _obj(_obj(endpoint)['likeEndpoint']);
    final id = _str(_obj(like['target'])['playlistId']);
    return id.isEmpty ? null : id;
  }

  void visit(Object? value) {
    if (value is List) {
      for (final item in value) {
        visit(item);
      }
      return;
    }
    for (final entry in _obj(value).entries) {
      final r = _obj(entry.value);
      switch (entry.key) {
        case 'toggleButtonRenderer':
          final id =
              likeTarget(r['defaultServiceEndpoint']) ??
              likeTarget(r['toggledServiceEndpoint']);

          if (id != null && saved == null) {
            playlistId ??= id;
            saved = r['isToggled'] == true;
          }
        case 'likeButtonRenderer':
          final id = _str(_obj(r['target'])['playlistId']);
          if (id.isNotEmpty && saved == null) {
            playlistId ??= id;
            saved = r['likeStatus'] == 'LIKE';
          }
        case 'likeEndpoint':
          playlistId ??= _str(_obj(r['target'])['playlistId']).isEmpty
              ? null
              : _str(_obj(r['target'])['playlistId']);
        default:
          if (entry.value is Map || entry.value is List) visit(entry.value);
      }
    }
  }

  visit(raw);
  if (playlistId == null) {
    final canonical = _str(
      _at(raw, ['microformat', 'microformatDataRenderer'])['urlCanonical'],
    );
    final list = Uri.tryParse(canonical)?.queryParameters['list'];
    if (list != null && _resourceId.hasMatch(list)) playlistId = list;
  }
  debugPrint('ytm_album_library playlist=${playlistId != null} saved=$saved');
  return YtmAlbumLibrary(playlistId, saved ?? false);
}
