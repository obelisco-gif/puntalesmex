# Cambio de email en conversación

Corregido el 5 de noviembre de 2026. Una petición explícita como «mejor me suscribes en el mail…» puede sustituir el email principal del mismo contacto. El sistema valida la dirección literal del mensaje guardado y la petición de cambio. Si la dirección pertenece a otra ficha, mantiene la revisión humana. La sustitución conserva UUID, teléfono, etiquetas, historial y datos comerciales.

El cambio se audita con dirección anterior, nueva y petición original. El permiso anterior no se transfiere automáticamente: cambiar un correo sin pedir comunicaciones deja el permiso del nuevo correo como desconocido. Si pide además la suscripción, se guarda evidencia explícita para el nuevo email.

Cada trabajo de Klaviyo queda ligado al email que debe suscribirse y tiene una clave idempotente por contacto y dirección. Los trabajos pendientes de una dirección sustituida se cancelan; los errores históricos permanecen en su trabajo original. El estado mostrado a los agentes corresponde al correo actual.

El perfil de Klaviyo se crea o actualiza por email. El identificador del CRM se guarda como propiedad sadiet_contact_id; no se usa como external_id ni se envía el teléfono en esta operación de email, para evitar fusionar el nuevo correo con el perfil bloqueado anterior.

La prueba real solicitada conservó la ficha y generó un perfil nuevo (HTTP 201); Klaviyo aceptó la solicitud de suscripción (HTTP 202). La pertenencia se verifica después por la API de listas del perfil, porque la suscripción es asíncrona. Solo membership_confirmed=true permite confirmar el alta al contacto. No se retiran rebotes ni otras supresiones del perfil anterior.

Pruebas locales: sustitución explícita, conservación de identidad, nuevo trabajo independiente, historial del rebote anterior, repetición sin duplicar cambios, conflicto real con otra ficha, permiso no heredado y perfil remoto seleccionado por dirección.
