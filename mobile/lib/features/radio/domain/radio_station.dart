import '../../search/domain/catalog_track.dart';

/// Una emisora de radio de internet: su nombre, su dial y la dirección del
/// flujo en directo, con los dos colores que la representan.
class RadioStation {
  const RadioStation({
    required this.id,
    required this.name,
    required this.stream,
    this.frequency,
    this.colors = const [0xFF3B4A6B, 0xFF1B2236],
    this.logo,
    this.nowPlaying,
    this.moods,
    this.zoneStream,
  });

  /// Una plantilla `https` con `{zone}` (`minus05`, `plus00`…) para emisoras que
  /// tienen una señal por huso horario (ROVR): cada una lleva la programación
  /// de su hora local, así que se usa la del teléfono, como hace su web. Sin
  /// ella (o sin zona válida) se usa [stream].
  final String? zoneStream;

  /// El nombre de la zona de [offset] como lo escribe ROVR: `minus05`, `plus00`,
  /// `plus11`. Solo huso en horas enteras, de -10 a +12 (las que tiene).
  static String zoneName(Duration offset) {
    final hours = offset.inHours.clamp(-10, 12);
    final digits = hours.abs().toString().padLeft(2, '0');
    return hours < 0 ? 'minus$digits' : 'plus$digits';
  }

  /// Una dirección `https` con la lista de moods (otras señales de la misma
  /// emisora: ROVR tiene DRIVE, THINK, FEEL y MOVE). Con ella, el reproductor
  /// muestra pastillas «Radio · mood · mood…» para cambiar de señal.
  final String? moods;

  /// Una dirección `https` que da, en JSON, lo que suena ahora (programa,
  /// título, artista y carátula). Las emisoras que no la tienen usan solo los
  /// metadatos del flujo.
  final String? nowPlaying;

  /// El logo de la emisora: un recurso de la app (`assets/images/…`) o una
  /// dirección `https`. Sin él se ve solo el degradado.
  final String? logo;

  static final _logo = RegExp(r'^assets/images/[A-Za-z0-9_.-]{1,80}$');

  /// [logo] si es uno que se puede pintar; si no, null.
  static String? validLogo(Object? value) {
    if (value is! String) return null;
    if (_logo.hasMatch(value)) return value;
    final uri = Uri.tryParse(value);
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.hasFragment
        ? value
        : null;
  }

  /// Shonan Beach FM, de Kanagawa (Japón): 78.9 FM. El flujo es el de su
  /// emisión en directo (MP3 a 128 kbps, por `https`).
  static const shonanBeachFm = RadioStation(
    id: 'shonan-beach-fm',
    name: 'Shonan Beach FM',
    frequency: '78.9',
    stream: 'https://shonanbeachfm.out.airtime.pro/shonanbeachfm_a',
    // El mar y el cielo de la playa: del agua clara al azul hondo.
    colors: [0xFF0FA3B1, 0xFF164B7E],
    // El logo oficial en blanco (del sitio de la emisora), sobre el degradado.
    logo: 'assets/images/radio-shonan-beach-fm.png',
    // El mismo archivo que lee su reproductor web: se actualiza cada canción.
    nowPlaying: 'https://www.beachfm.co.jp/wp-content/uploads/now_play.json',
  );

  /// KDVS, la radio libre de la Universidad de California en Davis: 90.3 FM.
  /// Flujo AAC a 128 kbps por `https`; su web lee lo que suena de Spinitron.
  static const kdvs = RadioStation(
    id: 'kdvs',
    name: 'KDVS',
    frequency: '90.3',
    stream: 'https://listen.kdvs.org/stream',
    // El gris carbón de su web (#2c2c2c): el logo es un círculo negro.
    colors: [0xFF6B6B6B, 0xFF2C2C2C],
    logo: 'assets/images/radio-kdvs.png',
    nowPlaying: 'https://kdvs.org/api/spinitron/nowplaying',
  );

  /// ROVR («Radio Reinvented»): radio 24/7 con programas de curadores. Emite por
  /// HLS, una señal por huso horario; esta es la principal de su web (UTC, 320
  /// kbps AAC). No tiene dial. Lo que suena sale de su programación pública
  /// (`date=now` se cambia por la hora UTC de cada consulta).
  static const rovr = RadioStation(
    id: 'rovr',
    name: 'ROVR',
    stream: 'https://hls-prod.rovr.live/prod/stream_plus00/llhls.m3u8',
    // El amarillo de su logo (#FFF057) y uno algo más hondo. El logo es el de
    // las placas en negro con las letras recortadas, para verse sobre amarillo.
    colors: [0xFFFFF057, 0xFFF2CC1C],
    logo: 'assets/images/radio-rovr.png',
    nowPlaying: 'https://strapi.rovr.live/api/schedules/radio/public?date=now',
    moods: 'https://strapi.rovr.live/api/streams/moods/public',
    zoneStream: 'https://hls-prod.rovr.live/prod/stream_{zone}/llhls.m3u8',
  );

  /// Las emisoras con las que arranca la app, hasta que el usuario cambie la
  /// lista.
  static const defaults = [shonanBeachFm, kdvs, rovr];

  final String id;
  final String name;

  /// La dirección del flujo en directo.
  final String stream;

  /// El dial, solo el número (`78.9`); sin él, la emisora no tiene frecuencia.
  final String? frequency;

  /// Dos colores ARGB: el degradado del bloque.
  final List<int> colors;

  /// Lo que se ve bajo el nombre: «78.9 FM»; sin dial, «EN VIVO».
  String get label => frequency == null ? 'EN VIVO' : '$frequency FM';

  /// El flujo si es una dirección que se puede reproducir (`https`, sin
  /// usuario ni fragmento; los parámetros sí se permiten).
  Uri? get streamUri => validStream(stream);

  /// El flujo que suena en el huso [offset] del teléfono (por defecto, el
  /// suyo): el de su zona si la emisora tiene una por huso, y si no, [stream].
  Uri? streamFor([Duration? offset]) {
    final template = zoneStream;
    if (template == null) return streamUri;
    final zone = zoneName(offset ?? DateTime.now().timeZoneOffset);
    return validStream(template.replaceAll('{zone}', zone)) ?? streamUri;
  }

  /// Cómo suena como pista del reproductor: en directo, sin duración, sin
  /// pasar por YouTube. [offset]: el huso del teléfono (solo lo cambian las
  /// pruebas).
  CatalogTrack toTrack({Duration? offset}) => CatalogTrack(
    id: '${CatalogTrack.livePrefix}$id',
    title: name,
    artistName: label,
    liveStream: streamFor(offset),
    liveColors: colors,
    liveLogo: logo,
    liveInfo: nowPlaying == null ? null : validStream(nowPlaying!),
    liveMoodsUrl: moods == null ? null : validStream(moods!),
  );

  static final _frequency = RegExp(r'^\d{2,3}([.,]\d{1,2})?$');
  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  static Uri? validStream(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return null;
    }
    return uri;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'stream': stream,
    'frequency': frequency,
    'colors': colors,
    'logo': logo,
    'nowPlaying': nowPlaying,
    'moods': moods,
    'zoneStream': zoneStream,
  };

  /// null si los datos no valen (así un archivo dañado no rompe la lista).
  static RadioStation? fromJson(Object? data) {
    if (data is! Map) return null;
    final id = data['id'], name = data['name'], stream = data['stream'];
    if (id is! String ||
        !_id.hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80 ||
        stream is! String ||
        validStream(stream) == null) {
      return null;
    }
    final frequency = data['frequency'];
    final colors = data['colors'];
    // Una lista guardada antes de que hubiera logos: la de fábrica lo conserva.
    final logo =
        validLogo(data['logo']) ??
        defaults.where((d) => d.id == id).firstOrNull?.logo;
    final info = data['nowPlaying'];
    final factory = defaults.where((d) => d.id == id).firstOrNull;
    return RadioStation(
      logo: logo,
      nowPlaying: info is String && validStream(info) != null
          ? info.trim()
          : factory?.nowPlaying,
      moods: data['moods'] is String && validStream(data['moods']) != null
          ? (data['moods'] as String).trim()
          : factory?.moods,
      zoneStream:
          data['zoneStream'] is String &&
              (data['zoneStream'] as String).contains('{zone}') &&
              validStream(
                    (data['zoneStream'] as String).replaceAll(
                      '{zone}',
                      'plus00',
                    ),
                  ) !=
                  null
          ? (data['zoneStream'] as String).trim()
          : factory?.zoneStream,
      id: id,
      name: name.trim(),
      stream: stream.trim(),
      frequency: frequency is String && _frequency.hasMatch(frequency)
          ? frequency.replaceAll(',', '.')
          : null,
      colors:
          colors is List && colors.length == 2 && colors.every((c) => c is int)
          ? [for (final c in colors) c as int]
          : const [0xFF3B4A6B, 0xFF1B2236],
    );
  }
}
