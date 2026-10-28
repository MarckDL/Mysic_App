# Sprint 05 — Plan y ejecución de viabilidad de reproducción

Fecha: 25 de octubre de 2026. Historia: US-005.
Estado: demo y CI verificadas; publicación de etiqueta pendiente.
Versión prevista: sprint-05-v0.5.0.

## Objetivo

Validar reproducción nativa con una fuente de audio autorizada, resolución explícita
de disponibilidad y manejo de errores/interrupciones antes del reproductor completo.
Base: Sprint 05 del roadmap, arquitectura y requisitos RF-017/RF-024, soporte
inicial de RF-018/RF-023. No declarar terminado el reproductor del Sprint 06.

## Plan y orden

1. Formalizar PlaybackResult y POST /api/v1/playback/resolve autenticado.
2. Registrar una fuente demo autorizada y mantener YouTube como metadatos sin
   extracción ni retransmisión. No usar cookies ni tokens de proveedor.
3. Generar un WAV sintético propio, reproducible, con licencia y procedencia.
4. Incorporar just_audio y audio_session; pantalla de prueba con cargar, reproducir,
   pausar y reiniciar. No autoplay, cola, mini player ni servicios en segundo plano.
5. Probar resolución, errores, pausas por interrupción/background y liberación
   del reproductor al salir/cambiar de cuenta.
6. Validar audio audible en Android con el usuario, APK y CI; registrar decisión.
7. Publicar commit y etiqueta solo después de completar aceptación.

## Decisiones de fuente y contrato

La demo usa el archivo empaquetado assets/audio/mysic-demo.wav. Es una secuencia
sintética generada para Mysic, sin muestras de música externa. La resolución devuelve
mode=direct, delivery=asset y assetPath exacto. No acepta URLs arbitrarias ni rutas
locales elegidas por Flutter. Este resultado extiende el contrato conceptual direct
para expresar entrega local, sin simular un enlace HTTPS.

Se conservan los modos embedded/unavailable, pero no se incorpora reproductor
embebido en este sprint. Las pistas YouTube responden unavailable con motivo claro:
los metadatos y los derechos de reproducción son cuestiones independientes.
No se implementa descifrado de URLs, descarga, proxy, DRM ni evasión de restricciones.

La demo se resuelve mediante MusicProvider y un registro explícito de fuentes.
No se incorpora a la búsqueda YouTube ni se persiste como pista del usuario.
La prueba de asset valida decodificación/reproducción nativa; no demuestra streaming
remoto, HTTP Range, CDN, autenticación de medios ni continuidad en segundo plano.

## Endpoint

POST /api/v1/playback/resolve
Authorization: Bearer Firebase ID token
Body: { source: "demo", sourceId: "mysic-tone-v1" }

Para YouTube: source="youtube" y sourceId del catálogo. Solo esos dos campos.
200: resultado de disponibilidad, incluso unavailable; 400: entrada inválida;
401/403: autenticación; 429: límite por UID; 503/504: fallo operativo/timeout.
Respuestas no-store. Resoluciones no se persisten ni se cachean como URLs duraderas.

## Prueba manual Android pendiente

- Entrar con cuenta válida, abrir Prueba de audio desde inicio y cargar demo.
- Reproducir con volumen moderado: debe oírse una secuencia de tonos durante 8 s.
- Pausar/reanudar, terminar y reiniciar. No debe quedarse en carga.
- Salir de la pantalla y cambiar/cerrar cuenta: el audio se detiene.
- Enviar la app al fondo: se pausa; al volver requiere acción explícita para seguir.
- Abrir otra app de audio/llamada de prueba y verificar pausa, sin reanudación automática.
- Si hay auriculares disponibles, desconectarlos y confirmar pausa.
- Desde una pista YouTube, consultar disponibilidad: debe explicar indisponibilidad.
- Probar backend apagado durante carga: error/reintento sin cerrar sesión Firebase.
- Registrar qué interrupciones se pudieron probar en emulador y cuáles requieren
  dispositivo físico; no dar por probado hardware que no esté disponible.

## Criterios de aceptación

- Fuente autorizada reproducible y audible en Android.
- Resolución autenticada, contrato validado y errores operativos controlados.
- Audio detenido al abandonar sesión/pantalla; interrupciones y errores probados.
- Decisión técnica escrita con límites de la evidencia y pendientes de streaming.
- Suites y APK correctos en CI; etiqueta publicada/verificada al cierre.

## Incidencia de recursos gráficos de tests

El usuario ejecutó análisis sin problemas y la suite móvil: 25 pruebas correctas,
2 fallidas al pulsar botones por ink_sparkle.frag con etapas Vulkan y backend SkSL.
La cadena && se detuvo antes de flutter run; esto explica que el emulador conserve
una instalación anterior. No es evidencia de regresión del login ni del catálogo.

Se eliminaron únicamente mobile/build/unit_test_assets y mobile/build/test_cache
para forzar reconstrucción. El código Flutter instalado comprueba vigencia de estos
assets mediante el manifest, sin comparar el backend gráfico. Siguiente verificación:
flutter test --no-enable-impeller, seguido de flutter run con configuración Firebase.
No se han cambiado controles ni expectativas para ocultar la excepción.

Siguen pendientes audio audible/interrupciones Android, decisión final de viabilidad,
CI y cierre. El inicio del Sprint 06 queda condicionado a esos resultados.

## Decisión de viabilidad y ajuste de alcance

El usuario confirmó que el Sprint 05 funciona correctamente y pidió su cierre.
Esto se registra como validación manual global de la demo, no como observación
directa del agente de cada escenario ni confirmación específica de auriculares
físicos o llamadas. Esos escenarios de hardware quedan para la prueba ampliada
Android del Sprint 06 cuando se disponga del dispositivo correspondiente.

Decisión: mantener just_audio/audio_session para reproducción nativa autorizada.
La demo valida la ruta de integración y el audio local empaquetado. No acredita
streaming HTTPS, reproducción del catálogo YouTube ni continuidad al bloquear
pantalla. Actualmente YoutubeProvider.resolvePlayback devuelve unavailable de
forma deliberada y no intenta obtener URLs de audio.

Por acuerdo explícito del usuario, la prueba de audio real con youtubei.js pasa
al inicio del Sprint 06: resolver una fuente propia/autorizada, verificar acceso
y reproducción en Android y documentar bloqueos si aparecen. La capacidad de la
biblioteca no es una prueba de que funcione para cada pista/entorno. No se garantiza
una integración antes de realizar esa comprobación. Roadmap actualizado.

## Revisión técnica de cierre

- Backend: resolución protegida, whitelist de asset, timeout y límite por UID.
- Flutter: sin autoplay; respuestas de otra cuenta descartadas; pausa por foco,
  ruido/background; motor liberado al salir. POST no se reintenta automáticamente.
- Asset propio con generador, CC0 y formato WAV verificado por prueba Python.
- No hay migraciones ni nuevas credenciales. Dependencias y lockfile móviles incluidos.
- CI configurada con flutter test --no-enable-impeller para usar backend de shaders
  consistente en tests; el build APK conserva su configuración Android normal.
- Los resultados exactos de suites y CI se registrarán antes de etiquetar.
- Falta verificar CI y publicar el registro/etiqueta. No se declara cerrado todavía.

### Resultado de revisión local

Backend: lint, typecheck, format:check y build correctos; 101 tests correctos y
3 PostgreSQL omitidos localmente (se ejecutarán en la base desechable de CI).
Python: 5 pruebas correctas, incluido formato/señal del WAV. Dart: 37 archivos
sin cambios de formato y análisis sin problemas. git diff --check correcto;
escaneo de patrones sensibles sin coincidencias. El escaneo no garantiza detectar
todos los secretos y complementa las exclusiones y revisión de cambios.

flutter test --no-enable-impeller se intentó desde el ejecutor y quedó bloqueado
antes de ejecutar por caché del SDK en filesystem de solo lectura. No se declara
la suite móvil completa pasada a partir de ese intento; la CI será obligatoria.
La validación manual de la demo fue confirmada por el usuario.

## Validación remota final

Commit probado: `912823e209fddafd4f0ba9094f2dea40a7249a3b`.
Quality: https://github.com/MarckDL/Mysic_App/actions/runs/40612971829

Workflow completado con success. Backend: 104 pruebas correctas, incluidas las
3 de PostgreSQL sin omisiones; migración, generación Prisma, lint, tipos, formato
y build correctos. Mobile: formato, análisis, suite Flutter con backend de shaders
consistente, 5 pruebas Python y compilación APK debug correctos. El fallo anterior
de ink_sparkle no se reprodujo en esta CI. La demo real fue validada por el usuario.

Este resultado actualiza los pendientes históricos de pruebas y CI del documento.
La resolución real de audio de youtubei.js sigue trasladada al Sprint 06 por acuerdo
expreso; este cierre no afirma reproducción de pistas YouTube ni streaming remoto.

Falta publicar el registro y la etiqueta anotada sprint-05-v0.5.0 sobre el commit
probado. Verificar la referencia remota antes de declarar cerrado el Sprint.
