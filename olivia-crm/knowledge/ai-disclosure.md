# Aviso inicial de apoyo de IA

Texto exacto: Nota: este chat puede contar con apoyo de ia

Se añade automáticamente antes de la primera salida automatizada de Olivia a un contacto. El mensaje de respuesta queda retenido hasta que WhatsApp acepta el aviso. Tras esa aceptación, el outbound recoge inmediatamente la respuesta original, en un segundo mensaje. Una vez confirmado, no vuelve a avisar al mismo contacto en otros turnos o conversaciones.

En contacts se guardan ai_disclosure_shown, ai_disclosure_shown_at, ai_disclosure_version, ai_disclosure_dispatch_id y ai_disclosure_external_id. preferences.ai_disclosure conserva el texto y estado, accesibles al contexto del agente. El CRM muestra la confirmación y fecha. Encolar no equivale a notificar: un fallo o un envío sin identificador no marca informado ni libera la respuesta. No se reintenta automáticamente un resultado incierto.

Las respuestas manuales del equipo y los avisos internos de handoff no generan este aviso. Los mensajes automáticos pendientes anteriores también quedan protegidos; no se presume que los contactos históricos ya hayan sido informados.

Dentro de la ventana de respuesta se envía el texto exacto como mensaje libre. Fuera de la ventana, el aviso utiliza la plantilla propuesta olivia_aviso_ia (es), con ese mismo texto y sin parámetros. La plantilla no está creada ni aprobada en Meta: el inicio queda retenido hasta confirmar ai_disclosure.template_approved=true con su nombre e idioma reales. No se añade texto a una plantilla ajena ya aprobada.

La nota la envía el sistema, no la redacta el modelo. No activa envíos ni concede consentimiento comercial. Se conserva el interruptor de WhatsApp y los permisos por canal. Un STOP no provoca promoción; la confirmación de baja mantiene sus restricciones.
