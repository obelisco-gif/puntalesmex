# Dispatcher de salida de Olivia

Revisado el 5 de noviembre de 2026. Dina se ha consultado como referencia y no se ha modificado.

El flujo principal guarda la respuesta en `outbound_dispatches` y llama inmediatamente a «Olivia · 02 Envío WhatsApp» con su `dispatch_id`. El mismo dispatcher se ejecuta cada dos minutos para recuperar pendientes, reservas interrumpidas y reintentos programados. No genera ni reescribe la respuesta del agente.

Recorrido: preparar altas autorizadas y avisos → reparar dependencias canceladas → reclamar una salida con bloqueo exclusivo → reservar un único intento → switch por tipo → enviar → registrar resultado → reclamar la siguiente. Cada ejecución procesa como máximo veinte mensajes; el resto queda para la siguiente activación.

El switch tiene cinco salidas: imagen, aviso interno al equipo, plantilla, texto y rechazo de datos incompletos. El texto incluye respuestas de Olivia, respuestas humanas, aviso IA, seguimientos y enlaces. Las plantillas conservan nombre, idioma y componentes propios de cada mensaje; los nombres adicionales se autorizan en `olivia_config.outbound_templates`. Las imágenes requieren `payload.kind=image`, URL HTTPS en `image_url` y, opcionalmente, `caption`. No se copian números, credenciales ni recursos de Dina.

El texto y las variables provienen del mensaje reclamado. La credencial de envío es «Cafe WhatsApp account» y la base de datos es Postgres Sadiet. El emisor se obtiene de la configuración de Olivia.

Antes de la primera respuesta automática se envía por separado «Nota: este chat puede contar con apoyo de ia». El contacto solo se marca como notificado cuando WhatsApp devuelve un identificador de aceptación. La respuesta dependiente se reclama inmediatamente después. Si una prueba antigua canceló el aviso, se crea uno nuevo antes de enviar una respuesta nueva. Un aviso fallido con resultado incierto requiere revisión.

Los estados conservan aceptación o error real del proveedor. Solo los rechazos explícitos por límite de uso se reintentan automáticamente, con espera creciente y un máximo de tres intentos. Las reservas caducadas sin intento de envío se recuperan; los intentos cuyo resultado se desconoce pasan a fallo para revisión, sin reenvío ciego. Las ejecuciones simultáneas no reclaman el mismo mensaje.

Se conservan las reglas de STOP, permisos, ventana de WhatsApp y control humano. El acuse de derivación de Olivia puede salir mientras el caso está pendiente de atención; al tomar el control una persona, las respuestas automáticas quedan bloqueadas. Los avisos internos al equipo siguen pendientes de un número confirmado y una plantilla aprobada.

Estado operativo tras la revisión: WhatsApp habilitado por indicación del usuario. Se cancelaron siete mensajes anteriores de prueba conservando historial y siete eventos de auditoría. La nueva prueba produjo dos aceptaciones de WhatsApp en la misma ejecución: aviso IA y respuesta, cada uno con un intento y sin error. Se verificó también la reserva y el reintento en una transacción de prueba revertida, sin envíos, y las pruebas locales de tipos, parámetros, control humano y dependencias.
