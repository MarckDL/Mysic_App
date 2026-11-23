# 27 — Reproductor al estilo de Limusic Android

El reproductor a pantalla completa y el mini reproductor reproducen los de
Limusic Android (`SimoHypers/limusic-android`, rama `dev`, commit `7de0ded`),
leídos de su código fuente abierto. Limusic tiene tres estilos; se replicó el
que trae por defecto, «Classic» (`NowPlayingContentLimusic.kt`).

Código (en `mobile/lib/features/playback/`):

- `presentation/player_screen.dart` — la página.
- `presentation/player_carousel.dart` — la portada y sus vecinas.
- `presentation/playback_progress.dart` — la barra ondulada.
- `presentation/player_sheets.dart` — temporizador, velocidad y tono,
  información.
- `presentation/player_widgets.dart` — el mini reproductor.
- `application/track_playback_controller.dart` — temporizador, velocidad y
  tono.

Pruebas: `test/player_screen_test.dart`, `test/playback_progress_test.dart`.

## 1. La página

De arriba abajo, sin desplazamiento:

| Parte | Limusic | Mysic |
| --- | --- | --- |
| Fila superior | Cerrar, «Now playing», salida de audio | Cerrar, «Reproduciendo», salida de audio |
| Portada | `CoverPager`: una por página, sombra, 24 dp de margen | `PlayerCoverCarousel`: igual de grande, pero con la anterior y la siguiente asomando a los lados (a petición; en Limusic no asoman) |
| Línea de letra | `CoverLyricLine` | La línea que suena, si la letra es sincronizada |
| Título | Título con el corazón en su línea; artista debajo | A petición, como estaba en Mysic: el artista encima del título y el álbum debajo, ambos como enlace; el corazón en la línea del título |
| Progreso | `WavySeekBar` | `WavyTrackShape` sobre el `Slider` |
| Transporte | Tres píldoras: 80×64, 120×80, 80×64 | Igual |
| Fila inferior | Cuadrados de 44 dp: guardar, repetir, letra, aleatorio, cola; menú relleno de 46 dp | Igual |

Gestos de la portada: deslizar a los lados cambia de canción, deslizar hacia
arriba abre la cola, dos toques dan Me gusta (con un corazón que aparece y se
va) y mantener pulsado abre el menú.

**Cola y Letra son vistas de la misma página** (`ClassicView`): ocupan el sitio
de la portada con un fundido de 300 ms y los controles se quedan donde están.
En esas vistas las píldoras de transporte se recogen tras 4 s sin tocar y un
toque las devuelve. Atrás vuelve a la portada antes de cerrar el reproductor.

El fondo sigue siendo la portada desenfocada con el color adaptado
(`PlayerBackdrop`), que ya existía.

## 2. Barra ondulada

Lo ya sonado es una onda que avanza una longitud por segundo; lo que falta, una
línea recta. La onda se aplana al pausar y al arrastrar, y el tirador pasa de
círculo de 14 dp a barra de 6×22. Se dibuja como forma de pista del mismo
`Slider`, que conserva los gestos y la accesibilidad. Con «Reducir efectos» la
barra es plana y no se anima.

## 3. Menú de la canción que suena

Es la hoja de canción de siempre (doc 26) más las filas propias del reproductor:

- **Temporizador de apagado**: 5, 10, 15, 30, 45 min, 1 hora, «Fin de la
  canción» o minutos a medida. En marcha muestra lo que queda y a qué hora se
  pausa, con «+10 min» y «Apagar».
- **Velocidad y tono**: de x0,2 a x2 en pasos de 0,1 y de -12 a 12 semitonos.
- **Información de la canción**: título, artista, álbum, duración, descarga e
  identificador.
- **Detener reproducción** (propia de Mysic).

## 3 bis. Precarga de portadas

Como ya se hacía con el audio, también se precargan las portadas: la de la
canción que suena y las 5 anteriores y 5 siguientes de la cola, de la más cercana
a la más lejana (`presentation/artwork_prefetch.dart`). Se descargan a la caché
de disco y se decodifican al tamaño exacto con que las pinta el reproductor, y
lo mismo con el fondo desenfocado. Así, al deslizar, saltar de canción o abrir el
reproductor, ninguna se ve cargar.

La precarga arranca desde el mini reproductor, antes de abrir la pantalla
completa, y se repite al cambiar de canción. Lo ya pedido no se vuelve a pedir.
Sin red, o con «solo canciones descargadas», no hace nada.

Medido en el teléfono con canciones nunca vistas: 250 ms después de pulsar
Siguiente, la portada nueva, sus dos vecinas y el color del fondo ya estaban
pintados.

## 3 ter. Desvanecido al pausar

Al pausar el usuario una canción que suena, el volumen baja hasta cero en medio
segundo (10 pasos de 50 ms) y entonces se pausa; el icono cambia al instante. Al
reanudar suena con el volumen entero. Reanudar, cargar otra canción o detener
durante el desvanecido lo cancela y devuelve el volumen.

Solo lo usa la pausa pedida por el usuario (botón, notificación, auriculares,
temporizador de apagado). Las interrupciones (una llamada, desconectar los
auriculares) pausan al instante. Es la interfaz `TrackAudioFade` del motor
(`pauseFading`), que `JustAudioTrackEngine` implementa; el controlador la usa
con `TrackPlaybackController.pauseFade`.

Pruebas: `test/pause_fade_test.dart`.

## 4. Mini reproductor

Como `LimusicMiniPlayer`: tarjeta de radio 10, miniatura de 42 dp, corazón,
botón redondo de reproducir, siguiente y la línea de avance de 2 dp. Tocar o
deslizar hacia arriba abre el reproductor; deslizar a los lados cambia de
canción. Se quitó la flecha de abrir.

## 5. Lo que no se replicó

- Los otros dos estilos de Limusic (M3 Expressive e Immersive) y su selector.
- Vídeo en lugar de portada y el interruptor Canción / Vídeo: Mysic solo
  reproduce audio.
- Compartir la letra como imagen, elegir la fuente de la letra y ajustar su
  desfase.
- El nombre de la lista de origen bajo «Reproduciendo».
- Cerrar el reproductor arrastrándolo hacia abajo (aquí es una pantalla, no una
  hoja).
- En «Información», los datos del flujo de audio (códec, tasa de bits…).
