# Vinculación oficial de YouTube · Fase 1

El backend autoriza una cuenta de YouTube elegida en el navegador. Firebase sigue identificando la cuenta de Mysic. La prueba de cobertura con dos cuentas en Perú enumeró nueve listas propias, cuatro privadas. Se leyeron dos listas privadas de once y cinco elementos y una lista pública de 68 en dos páginas de 50 y 18. Este resultado se obtuvo con Google OAuth Playground. El canje del nuevo callback requiere validación separada en staging.

## Flujo de la API

Prefijo `/api/v1/integrations/youtube`. Salvo los dos GET del navegador, los endpoints exigen un ID token de Firebase y un perfil sincronizado por el flujo existente. El UID verificado determina el propietario. Los DTO son privados y llevan `Cache-Control: no-store`.

| Método y ruta | Entrada y resultado |
| --- | --- |
| POST /link-attempts | Enviar `{}` con `Idempotency-Key` (UUID que el móvil reutiliza al reintentar). Devuelve `attemptId`, `launchUrl`, `expiresAt` y estado. La URL es de un uso. Un nuevo UUID sustituye los intentos previos del mismo usuario. |
| GET /browser/start | Consume `ref`, establece una cookie de correlación Secure, HttpOnly, SameSite=Lax y abre el consentimiento con PKCE S256, state y nonce. |
| GET /oauth/callback | Reclama el intento una sola vez, valida la cookie y el state, canjea el código y verifica firma RS256, emisor, audiencia, expiración, nonce y sujeto del ID token con las claves públicas de Google. Comprueba los alcances concedidos y el canal mediante channels.list. Devuelve una página sin recursos externos con retorno automático y enlace manual. |
| GET /link-attempts/{id} | Devuelve estado, motivo, canal candidato y vencimiento al propietario. Al iniciar el MVP móvil, guardar el ID del intento con su UID y vencimiento para recuperar el intento tras reiniciar la app. |
| DELETE /link-attempts/{id} | Cancela un intento del propietario. Devuelve 204 al repetir la cancelación y conserva un canal previamente vinculado. |
| POST /link-attempts/{id}/confirm | Retorno habitual con `{returnRef}`. Si se pierde la referencia, mostrar el canal de la consulta anterior y enviar `{channelId}` después del toque de confirmación. Para sustituir un canal o cuenta existente añadir `replace:true` y el ID elegido. Un reenvío tras confirmar devuelve el mismo resultado al propietario. |
| GET /connection | Estado `unlinked`, `linked`, `reauthorization_required` o `revocation_pending`. Si existe vínculo incluye canal, fecha, última comprobación y generación. |
| DELETE /connection | Invalida intentos y corta el acceso local en una transacción. Devuelve 204 al terminar o 202 cuando queda revocación pendiente. Permanece disponible con el flag apagado. |

El retorno usa el fragmento del App Link configurado, `#attemptId=…&returnRef=…`. El cliente móvil deberá extraer el fragmento y confirmar bajo el mismo UID. El navegador evita enviar el fragmento al servidor de destino. Si Google deniega el permiso o devuelve varios canales, el móvil consulta el motivo del intento. Para un canal ambiguo debe repetir el consentimiento eligiendo el canal correcto en Google. Si Google omite un refresh token, responder a `MISSING_REFRESH_TOKEN` ofreciendo un nuevo intento voluntario con `{forceConsent:true}`.

## Credenciales y concurrencia

Un intento vive diez minutos. La base guarda hashes de las referencias de navegador, del state y del nonce. AES-256-GCM protege el verifier, la referencia de lanzamiento reutilizable durante un reintento idempotente y los tokens de renovación. Los sobres autentican el propietario y el propósito o la generación. El access token permanece en memoria. Solo un propietario puede reservar un sujeto de Google en este entorno. Una revocación pendiente bloquea nuevas vinculaciones del mismo sujeto.

Los cambios breves de vínculo, intento y reserva de sujeto usan un bloqueo transaccional de PostgreSQL. El canje y la red de Google quedan fuera del bloqueo. Una renovación comparte la operación en una instancia y toma un lease de base de datos para coordinar instancias. Si otra instancia está renovando, se devuelve un error temporal. Una escritura tardía debe coincidir con la generación y el lease. Si se desvincula durante la renovación, el acceso local se corta inmediatamente y el trabajo de revocación espera la respuesta o el vencimiento del lease.

## Configuración del entorno

Valores nuevos solo en el backend. En staging, utilizar un cliente web del proyecto de integración, distinto del proyecto que gestiona el login de Firebase, y una base de datos aislada.

| Variable | Valor requerido |
| --- | --- |
| YOUTUBE_LINK_ENABLED | `true` permite crear y confirmar vínculos. El valor por defecto es `false`. Al apagar después de un piloto, conservar el resto de la configuración para desvincular y purgar. |
| YOUTUBE_OAUTH_CLIENT_ID | ID del cliente web de Google para este entorno. |
| YOUTUBE_OAUTH_CLIENT_SECRET | Secreto de ese cliente, custodiado en el gestor de secretos del entorno. |
| YOUTUBE_OAUTH_CALLBACK | URI HTTPS exacta registrada en Google Cloud, con la ruta del callback de la tabla anterior. |
| YOUTUBE_APP_RETURN | URL HTTPS fija del App Link, con ruta distinta del callback. |
| YOUTUBE_TOKEN_KEY_ID | Versión de clave activa. |
| YOUTUBE_TOKEN_KEYS | Objeto JSON que asocia cada versión a 32 bytes aleatorios en base64. Para rotar, añadir la nueva versión y mantener las anteriores mientras haya sobres que las usen, incluidos trabajos pendientes y copias de seguridad dentro de su retención. |

En Google Cloud habilitar YouTube Data API v3, definir público y testers según el entorno y registrar la URI exacta en **Clientes → Aplicación web → URI de redireccionamiento autorizados**. La solicitud del servidor pide `openid` y `youtube.readonly`, acceso offline y selección de cuenta. El cliente de Playground conserva su propósito de ensayo. Acordar retención y exclusión de query strings, cabeceras, cookies y cuerpos en los logs del proxy antes del canje real.

## Mantenimiento y aceptación en staging

Desde `backend/`, instalar las dependencias fijadas, generar Prisma, aplicar la migración en la base aislada y compilar. Ejecutar `pnpm youtube:maintain` con el mismo entorno del backend desde una tarea programada independiente del tráfico. Para el piloto se propone cada cinco minutos. Cada ejecución expira hasta 100 intentos, procesa hasta 50 trabajos vencidos y revalida hasta 50 vínculos con más de 24 horas desde la última comprobación. Los reintentos conservan estado en PostgreSQL. El resumen de operación contiene contadores. Alertar por fallos repetidos y por `youtube_revocation_unconfirmed_after_retention` cuando se purga una credencial tras siete días sin confirmar la revocación remota. En ese caso el propietario también puede retirar acceso desde las conexiones de Google. Verificar el proceso de borrado de cuenta antes de introducir una ruta que elimine usuarios.

Prueba de aceptación pendiente con recursos reales: iniciar con Firebase, autorizar una cuenta Google distinta, confirmar el canal, reiniciar el backend y renovar, retirar acceso en Google y comprobar reconexión, volver a vincular, desvincular desde Mysic y repetir el login Firebase. El retorno Android, consulta paginada de playlists en Mysic y prueba de actualización del APK corresponden a las fases siguientes. El proyecto externo en modo prueba puede expedir refresh tokens con vigencia de siete días.

Referencias oficiales: [OAuth web](https://developers.google.com/identity/protocols/oauth2/web-server), [OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect), [caducidad de credenciales](https://developers.google.com/identity/protocols/oauth2#expiration).
