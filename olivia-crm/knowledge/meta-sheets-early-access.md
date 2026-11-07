# Meta → EA26 → CRM → Klaviyo

Configurado el 5 de noviembre de 2026, solo para Olivia / Sadiet.

El flujo «Olivia · 00 Registro Meta → CRM» usa la credencial `Cafe Google Sheets Trigger account`, el documento EA26 y la pestaña «Hoja 1» (gid 0). El trigger comprueba nuevas filas cada minuto. El registro recibe ID del lead, fecha, email, nombre y apellidos, WhatsApp e identificación del formulario/anuncio/campaña. Conserva los IDs como texto; no supone un país si el móvil carece de prefijo.

La función de entrada deduplica por ID de Meta y por email/teléfono, guarda el contacto en el CRM y añade `bf2026_early_access`. Admite email sin móvil y móvil sin email. Los conflictos de identidad se rechazan para revisión.

El responsable confirmó que el formulario «early access 26» recoge consentimiento de email y WhatsApp. Esa confirmación administrativa, distinta de una transcripción del formulario, consta en `olivia_config.meta_ea26_form`. La política se aplica solo a EA26 / Hoja 1 y ese nombre de formulario. El primer ID real coincidente queda fijado; otro ID o formulario no hereda permisos. Cada canal requiere también el identificador correspondiente. Las futuras versiones con consentimiento parcial requieren su propia configuración. No se marca aceptación de privacidad por inferencia.

Los trabajos por etiqueta se guardan en la cola de integración. «Olivia · 04 Tag Early Access → Klaviyo» está activo cada minuto y la sincronización está habilitada para la lista Early access 26 (UdE5aX), usando `klaviyo sadiet`. Solo suscribe a email cuando consta su permiso; comprueba bajas remotas y confirma pertenencia. La gestión de emails de bienvenida y calentamiento corresponde a los flows configurados en Klaviyo; conectar la lista no crea ni publica esos emails.

WhatsApp de bienvenida queda pendiente: en la configuración actual no hay nombre de plantilla ni aprobación confirmada. El alta y el permiso se guardan y la bienvenida espera a que se configure una plantilla aprobada. Las inscripciones aceptadas dentro de una conversación las confirma Olivia y no reciben esa bienvenida de formulario.

Verificado: acceso real a documento y cabeceras con la credencial indicada; Klaviyo devuelve HTTP 200 y confirma lista UdE5aX / Early access 26. Pruebas locales: columnas reales, ID sin pérdida de precisión, fechas, prefijo, registros con un canal, duplicados, fijación del ID del formulario y ausencia de herencia a otros formularios. Prueba de CRM y cola Klaviyo en Supabase dentro de una transacción revertida, sin suscripciones ni mensajes de prueba reales.

Los dos flujos están publicados. El siguiente envío real de prueba desde Meta permitirá confirmar el recorrido completo de una fila nueva. Este trigger no se utiliza como carga histórica masiva de filas anteriores.
