# Estado real del alta por email

Revisión del 5 de noviembre de 2026. En la prueba de conversación el CRM guardó correctamente el email y la aceptación explícita de avisos. Klaviyo devolvió un perfil existente suprimido por HARD_BOUNCE desde diciembre de 2024. El trabajo quedó bloqueado antes de solicitar la suscripción. No se ha retirado ninguna supresión ni cambiado el permiso del contacto.

Se distinguen inscripción general a Early Access, permiso de email y pertenencia confirmada a la lista. La etiqueta del CRM no demuestra que el email pueda recibir comunicaciones. El nuevo campo `email_signup`, leído por ambos agentes, indica no_email, consent_missing, pending, not_requested, blocked, failed o confirmed. Confirmed exige trabajo completado y membership_confirmed=true.

El flujo registra el motivo específico (hard_bounce, invalid_email, remote_unsubscribed, suppressed o profile_api_error). Las respuestas de Olivia deben confirmar solo lo realmente completado: guardar el correo y tramitar el alta mientras esté pendiente; reconocer un problema si está bloqueada; confirmar el alta por email solo cuando la pertenencia consta. El aviso de problema se usa cuando es relevante para el alta o la consulta, sin interrumpir preguntas sobre productos.

Los bloqueos por rebote o dirección inválida se mantienen. El permiso nuevo no elimina un problema de entrega. La API de Klaviyo para retirar supresiones solo quita USER_SUPPRESSED; HARD_BOUNCE e INVALID_EMAIL permanecen. Para continuar la prueba hay que usar un correo válido sin ese bloqueo o resolverlo en Klaviyo.

Fuentes: https://developers.klaviyo.com/en/reference/bulk_unsuppress_profiles y https://help.klaviyo.com/hc/en-us/articles/115005250408

Verificación: pruebas de estados de email, transmisión al segundo agente, distinción entre trabajo completado y pertenencia real, y clasificación de los motivos de bloqueo. Las pruebas no suscriben perfiles ni envían mensajes.
