# Sistema visual móvil y conexión opcional con YouTube

Estado: implementado en la rama `codex/mobile-ui-youtube-integration`, pendiente de
validación visual en dispositivo y de despliegue de la migración.

## Dirección visual

- Fondo `#F8F7FB`, superficies blancas y lilas, acento morado y texto oscuro.
- Controles táctiles de al menos 44 px, radios moderados y listas compactas.
- Navegación inferior: Inicio, Explorar, Biblioteca y Perfil.
- Mini reproductor encima de la navegación y reproductor completo negro con acento morado.
- Acceso Google/Firebase, Inicio, búsqueda, detalle, cola, playlists, favoritos,
  ratings y perfil comparten el mismo sistema.
- Estadísticas, comentarios, recientes, letras, artistas, álbumes y videos permanecen
  ocultos hasta que existan sus contratos y Sprints.

## Biblioteca de YouTube

La primera etapa usa únicamente la API oficial y OAuth incremental
`youtube.readonly`. La autorización temporal viaja en un header de la solicitud de
sincronización y nunca se persiste. Se importan playlists, elementos disponibles,
videos marcados con Me gusta y suscripciones.

Los datos se presentan con origen YouTube y en modo de solo lectura. Una playlist
remota puede duplicarse como playlist privada de Mysic. La operación de sincronizar
reemplaza el snapshot del usuario, por lo que es idempotente a nivel de registros.

No se prometen recomendaciones, historial completo ni la biblioteca específica de
YouTube Music porque la API oficial no los expone. La evaluación de InnerTube es
experimental y futura; no se envían cookies al backend ni se implementa escritura
bidireccional.

## Validación pendiente fuera del repositorio

1. Aplicar la migración en el entorno de pruebas.
2. Configurar el consentimiento y alcance de YouTube Data API en Google Cloud.
3. Instalar el APK y sincronizar una cuenta real.
4. Repetir la sincronización y confirmar que no aparecen duplicados.
5. Revisar pantallas pequeña/grande, texto ampliado y contraste en Android físico.

Los mockups históricos se conservan en `docs/design/` únicamente como material de
exploración; la referencia aprobada es el tema claro descrito aquí.
