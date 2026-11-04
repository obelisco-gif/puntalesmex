# Handoffs de Olivia y aviso interno

El CRM registra un caso cuando Olivia solicita ayuda o cuando el equipo toma el control. Guarda contacto, conversación, nombre confirmado, teléfono, email, fase, score, etiquetas, motivo, resumen, prioridad, responsable y seguimiento. Un caso abierto se actualiza sin duplicarse. Una nueva derivación tras cerrar el anterior crea un caso nuevo.

Los estados son pendiente, en atención, resuelta y cancelada. El control del chat es independiente: devolverlo a Olivia no resuelve el caso y resolver el caso no cambia automáticamente el control. El historial conserva cambios del equipo y el resultado de cada aviso.

## Plantilla preparada para crear en Meta

Nombre propuesto: `olivia_handoff_equipo`. Idioma: `es`. Categoría propuesta: utilidad, pendiente de revisión por Meta. No se ha creado ni aprobado en Meta.

Olivia necesita ayuda del equipo Sadiet.
Contacto: {{1}}
Teléfono: {{2}}
Motivo: {{3}}
Resumen: {{4}}
Ficha: {{5}}
Tipo: {{6}}

Pie: Aviso interno del equipo Sadiet.
Botón: Abrir conversación.
URL del botón: `https://olivia-crm-weld.vercel.app/?tab=conversaciones&conversation={{1}}`.

Parámetros del cuerpo: nombre (60 caracteres), teléfono (32), motivo (240), resumen (360), enlace al CRM, tipo. Los saltos y espacios repetidos se normalizan. El botón recibe el identificador real de la conversación. Las consultas sensibles se describen de forma genérica, sin detalles de salud.

## Pendiente antes de activar los avisos

1. El propietario indica y confirma el número del equipo. No se copia ningún destinatario de Dina.
2. Crear la plantilla con el cuerpo y botón anteriores, y comprobar la aprobación y el idioma real en Meta.
3. Configurar `olivia_config.handoff_alerts`: `recipient_phone` en formato internacional, `recipient_confirmed=true`, `template_name`, `template_language`, `template_approved=true`, `enabled=true`.
4. Comprobar la credencial WhatsApp de Sadiet y publicar la versión preparada del outbound de Olivia. El flujo ya estaba activo; los interruptores de envío al cliente y de avisos internos continúan desactivados.

El aviso usa `outbound_dispatches` con `kind=human_handoff_alert` y destinatario interno explícito. No tiene vínculo de mensaje, contacto ni conversación en esa cola: la correlación se conserva en el caso. Así no aparece en el historial del cliente ni utiliza por error su teléfono. El aviso respeta su propio interruptor y nunca toma destinatarios de los mensajes del cliente. Una baja comercial del cliente no cancela el aviso interno.

Solo se prepara un aviso por caso nuevo abierto y configurado. Los casos anteriores se importan sin notificaciones retrospectivas. Cerrar un caso cancela su aviso aún pendiente; un envío ya iniciado puede completarse. Los fallos quedan registrados sin reintentos ciegos.

## Referencia de Dina

Se consultó `outbound_message_dispatcher`, sin modificarlo. Contempla texto, imágenes, avisos de handoff, plantillas de seguimiento y recuperación manual, con reserva de comandos y persistencia del resultado. Olivia reutiliza su propio outbound para texto, plantillas y los nuevos avisos; no se han incorporado las campañas, imágenes, números ni reglas del proyecto de Dina.
