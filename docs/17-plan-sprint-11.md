# Sprint 11 — Rediseño de interfaz y navegación

## Objetivo

Dar acceso directo al catálogo y a la colección personal, con una portada basada
en la actividad de escucha y un minirreproductor disponible en las tres pestañas.

| Días | Trabajo |
| --- | --- |
| 1–2 | Revisar entorno Android, documentar el orden del roadmap y definir el mapa de navegación. |
| 3–5 | Implementar Inicio, Buscar, Biblioteca y Cuenta e integrar el minirreproductor. |
| 6–8 | Conectar las últimas cinco escuchas y aplicar los estilos de Material 3 a las vistas principales. |
| 9–10 | Ejecutar análisis, pruebas y compilación Android, aceptar en el teléfono y publicar la versión verificada. |

## Aceptación física

1. Entrar con una cuenta Google y comprobar que la actividad reciente coincide con
   el historial. Abrir una canción desde Inicio y comprobar el regreso.
2. Buscar una canción, desplazarse por los resultados y recorrer las tres pestañas.
   Al volver a Buscar deben seguir visibles la consulta y la posición de la lista.
3. Abrir Biblioteca y comprobar los accesos de un toque a Playlists, Favoritos e
   Historial. Abrir un detalle desde una lista y volver a la misma posición.
4. Reproducir una pista compatible, recorrer las pestañas y abrir o cerrar el
   reproductor. Comprobar la cola, el progreso y los controles desde la
   notificación al enviar la app a segundo plano.
5. Cambiar a otra cuenta Google y comprobar que la actividad, biblioteca y
   búsqueda anteriores desaparecen. Verificar el acceso a moderación con y sin
   permiso.
6. Repetir la navegación con los temas claro y oscuro y el texto al 200 %.
   Probar Inicio con la red desconectada y comprobar el reintento al recuperarla.
   Registrar capturas con cuentas de prueba y sin datos personales.

## Cierre

La etiqueta prevista es `sprint-11-v0.11.0`. Publicarla tras completar la
aceptación física, revisar el diff y verificar las comprobaciones del repositorio.

## Evidencia de verificación

- `flutter analyze`, formato Dart y 78 pruebas Flutter correctas. Las pruebas
  cubren navegación, desplazamiento, reproducción simulada en segundo plano,
  cambio de cuenta, permiso de moderación y texto al 200 % en ambos temas.
- 11 pruebas de servicio y rutas de historial correctas. Las 3 pruebas con
  PostgreSQL local se omitieron porque el entorno no tenía una base de pruebas.
- APK de la versión 0.11.0 compilado para Android ARM64 y x86-64 con la URL
  HTTPS del backend. El servicio respondió HTTP 200 en salud y HTTP 401 en
  historial sin credenciales.
- En el emulador Pixel 7, una sesión Google existente abrió Inicio, Buscar,
  Biblioteca y Cuenta. Se verificó el regreso desde Playlists, Favoritos e
  Historial. Se capturaron la interfaz anterior y el rediseño durante la prueba.
  Las capturas de Biblioteca y del reproductor están en los resultados locales
  de compilación, bajo `mobile/build/reports/sprint-11/`.
- Una pista real del catálogo siguió reproduciéndose al cambiar de pestaña,
  abrir el reproductor y enviar la app a segundo plano en el emulador. El
  progreso superó 1:26, Android mostró la notificación multimedia y un comando
  multimedia cambió el estado de reproducción.

En Android físico (modelo 23117RA68G) se instaló 0.11.0 sobre la versión
anterior y se verificaron la sesión Google existente, los accesos de Biblioteca
y Cuenta, la reproducción real al pasar por las tres pestañas, la notificación
activa en segundo plano y los botones de reproducir y pausar en la notificación.
Inicio, Buscar y los accesos de Biblioteca se comprobaron con texto al 200 % en
ambos temas. Después de la prueba se restauró la configuración original del
teléfono. Las capturas del dispositivo se guardaron con las del emulador.

La aceptación con dos cuentas Google se completó en el mismo teléfono. Tras
cerrar la primera sesión e iniciar con la segunda, se verificaron perfiles
distintos, búsqueda vacía y acceso independiente a playlists e historial. Ambas
colecciones cargaron correctamente y las filas observadas en la primera cuenta
no aparecieron en la segunda.

La validación física anterior cubre el rediseño inicial. Después se rediseñó la
pantalla de acceso, se limitó el saludo a dos líneas y se añadió un editor de
apodo en Cuenta. El APK ARM64 se recompiló, pasaron 79 pruebas Flutter y 186
pruebas del backend, y las siete migraciones se aplicaron en una base
PostgreSQL de prueba. El despliegue debe aplicar la migración de Prisma antes de
servir el nuevo backend. Hay que probar el guardado y borrado del apodo en un
Android físico con ese backend antes de etiquetar la versión.

El Sprint 12 incorporará a Inicio rankings personales de canciones y artistas
y tendencias agregadas de Mysic, según el [roadmap](04-sprints-roadmap.md).
