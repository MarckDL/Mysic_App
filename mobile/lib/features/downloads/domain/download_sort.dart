import '../data/download_store.dart';

/// Los órdenes de las descargas, como los de Limusic (`DOWNLOAD_SORTS` en
/// `PlaylistSorting.kt`). «Más nuevas» y «Más antiguas» de Limusic son aquí el
/// predeterminado y su inverso (solo se sabe cuándo se descargó cada una), y
/// «Más escuchadas» no se ofrece: las descargas no guardan las escuchas.
enum DownloadSortKey {
  recent('Descargadas recientemente'),
  title('Título'),
  artist('Artista'),
  album('Álbum');

  const DownloadSortKey(this.label);

  final String label;
}

/// Un orden y si va invertido (Limusic: `ListSort(sort, desc)`).
class DownloadSort {
  const DownloadSort(this.key, {this.desc = false});

  static const initial = DownloadSort(DownloadSortKey.recent);

  final DownloadSortKey key;
  final bool desc;

  bool get isDefault => key == DownloadSortKey.recent && !desc;

  DownloadSort copyWith({DownloadSortKey? key, bool? desc}) =>
      DownloadSort(key ?? this.key, desc: desc ?? this.desc);

  /// Se guarda como «nombre» o «nombre:desc», igual que en Limusic.
  String encode() => desc ? '${key.name}:desc' : key.name;

  static DownloadSort decode(String? text) {
    if (text == null) return initial;
    final parts = text.trim().split(':');
    for (final key in DownloadSortKey.values) {
      if (key.name == parts.first) {
        return DownloadSort(key, desc: parts.length > 1 && parts[1] == 'desc');
      }
    }
    return initial;
  }

  /// [tracks] en este orden. Parte de la lista de la más reciente a la más
  /// antigua; los órdenes son estables, así que dentro de un mismo álbum (o
  /// título, o artista) se conserva ese orden. Sin álbum van al final, también
  /// invertido.
  List<DownloadedTrack> apply(List<DownloadedTrack> tracks) {
    final list = [...tracks]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    final dir = desc ? -1 : 1;
    switch (key) {
      case DownloadSortKey.recent:
        return desc ? list.reversed.toList() : list;
      case DownloadSortKey.title:
        return _stable(list, (a, b) => dir * compareText(a.title, b.title));
      case DownloadSortKey.artist:
        return _stable(list, (a, b) => dir * compareText(a.artist, b.artist));
      case DownloadSortKey.album:
        return _stable(list, (a, b) {
          final x = a.albumName?.trim() ?? '', y = b.albumName?.trim() ?? '';
          if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
          return dir * compareText(x, y);
        });
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DownloadSort && other.key == key && other.desc == desc;

  @override
  int get hashCode => Object.hash(key, desc);
}

/// Orden estable: `List.sort` de Dart no lo garantiza.
List<T> _stable<T>(List<T> items, int Function(T a, T b) compare) {
  final indexed = [for (final (i, item) in items.indexed) (i, item)];
  indexed.sort((a, b) {
    final result = compare(a.$2, b.$2);
    return result != 0 ? result : a.$1.compareTo(b.$1);
  });
  return [for (final (_, item) in indexed) item];
}

/// Compara textos como el `Collator` de Limusic con fuerza primaria: sin
/// distinguir mayúsculas ni tildes, y los números por su valor («Track 2»
/// antes que «Track 10»).
int compareText(String a, String b) {
  final x = _fold(a), y = _fold(b);
  final run = RegExp(r'\d+|\D+');
  final xs = run.allMatches(x).map((m) => m[0]!).toList();
  final ys = run.allMatches(y).map((m) => m[0]!).toList();
  for (var i = 0; i < xs.length && i < ys.length; i++) {
    final p = xs[i], q = ys[i];
    final pn = int.tryParse(p), qn = int.tryParse(q);
    final result = pn != null && qn != null ? pn.compareTo(qn) : p.compareTo(q);
    if (result != 0) return result;
  }
  return xs.length.compareTo(ys.length);
}

const _plain = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a', //
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', //
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', //
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', //
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', //
  'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
};

String _fold(String text) {
  final lower = text.trim().toLowerCase();
  final out = StringBuffer();
  for (final char in lower.split('')) {
    out.write(_plain[char] ?? char);
  }
  return out.toString();
}
