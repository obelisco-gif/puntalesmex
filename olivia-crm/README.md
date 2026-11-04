# Acceso privado de Olivia

Olivia usa Supabase Auth del proyecto Sadiet, independiente de Dina.
El administrador autorizado es `info@comprarcafeverde.es`, mediante
`CRM_ADMIN_EMAILS`. Solo las sesiones verificadas por Supabase y los emails
confirmados de esta lista pueden acceder a las API del CRM.

## Configuración

Configurar las variables de `.env.example` en el proyecto Vercel **olivia-crm**.
La clave de servicio se usa solo en el servidor para el CRM y nunca se publica.
La antigua clave compartida y su cookie ya no conceden acceso.

En Supabase Auth, configurar Site URL como
`https://olivia-crm-weld.vercel.app` y permitir el retorno exacto
`https://olivia-crm-weld.vercel.app/auth/callback?next=%2Freset-password`.
El proveedor Email debe estar activo y el envío de correos debe admitir al
administrador. El SMTP de prueba de Supabase puede limitar destinatarios;
para correo propio se necesita un proveedor SMTP configurado.

## Primer acceso y recuperación

Crear primero el usuario administrador desde Supabase Auth del proyecto Sadiet,
con email confirmado y una contraseña personal. Después entrar con ese email y
contraseña. La cuenta no se crea automáticamente desde el CRM.

Para recuperar una contraseña, introducir el email y pulsar **Recuperar contraseña**.
Supabase envía un enlace de un solo uso a la cuenta existente. Abrirlo en el mismo
navegador que lo solicitó para completar PKCE. El titular puede establecer una
contraseña nueva de al menos 12 caracteres. No hay registro público en el CRM ni
acceso para emails fuera de la lista.

La recuperación no cambia la contraseña hasta que el titular la guarda.
**Cerrar sesión** revoca la sesión local de Supabase y elimina la cookie
heredada del acceso antiguo. Las API vuelven a verificar al usuario en cada
solicitud; un fallo de Auth deniega acceso.

## Documentación con productos y temas

En Documentación, cada documento puede relacionarse con varios productos del
catálogo y tener varios temas independientes. Se pueden añadir temas nuevos
desde el editor. Comercial no excluye preparación, Black Friday o un producto.
Sin productos relacionados, el documento es general. Los estados siguen siendo
borrador, aprobado y archivado; el tema Uso interno excluye el documento de la IA.

La tabla product_document_products conserva las relaciones. El guardado de
contenido, estado, temas y productos usa una única transacción del servidor.
La columna antigua catalog_product_id se mantiene como referencia compatible.

El índice del nuevo núcleo de Olivia incluye temas e identificadores de los
productos relacionados. La consulta devuelve documentos específicos solo cuando
coincide uno de esos productos; los generales se buscan por tema. El validador
del primer agente acepta temas personalizados presentes en el índice, rechaza
temas inventados o internos y elimina los productos al tramitar STOP.

Los ajustes de n8n están exportados en n8n/document-routing.json y
n8n/permanent-base.json y aplicados al flujo publicado de conversación.
La lectura de documentación usa las relaciones de producto y los temas.

## Base permanente editable

Marcar el tema **Base permanente** en un documento general y aprobarlo hace que
ambos agentes reciban su contenido completo en cada turno. En el CRM existe
**Base permanente de comunicación y orientación comercial**, con idioma, tono,
saludos, políticas, resumen de la promoción y criterios de compra o Early Access.

El contenido se lee de product_documents al preparar el contexto de cada agente.
Una edición aprobada se aplica al siguiente turno sin volver a publicar n8n ni
Vercel. Borradores, archivados y documentos de uso interno no se inyectan.
La base es general y el editor exige dejar vacíos los productos relacionados.
Los detalles de producto y campaña se mantienen en los documentos específicos.

Las consultas de lectura están en database/permanent-base-read-queries.sql y los
ajustes de los agentes en n8n/permanent-base.json. La prueba
tests/permanent-base.sql confirma la lectura en ambas etapas, los cambios de
contenido inmediatos y la exclusión de documentos archivados o internos.

## Ficha comercial y registro dentro del chat

Contactos muestra ambos canales, nueve fases válidas, score automático con motivos
y ajuste manual, gustos, objeciones, horizonte de compra y memoria de Olivia.
contact_commercial_entries guarda intereses, descartes, consultas de pedido y
compras. Las compras confirmadas las registra el equipo con referencia; el chat
no puede confirmarlas. Reutilizar la referencia actualiza el registro.
El catálogo WooCommerce actual no importa pedidos ni compras automáticamente.

El contexto de ambos agentes incluye perfil, registros y score. El primer agente
propone cambios con evidencia literal; olivia_conversation_actions_b64 valida el
lote entrante reclamado y aplica las acciones antes del segundo agente. Una
oferta no da de alta: se exige aceptación. El alta guarda etiqueta y permiso de
WhatsApp y devuelve un resultado confirmado para que Olivia dé la bienvenida.
No genera otra bienvenida por plantilla. Si falta email, ofrece ese canal y pide
el correo; tener una dirección no equivale a tener permiso. Los conflictos de
identidad se derivan al equipo. Los reintentos recuperan la misma decisión.

Los cambios de perfil se combinan con la memoria existente y rechazan fichas
desactualizadas. Las funciones y la tabla comercial son de acceso exclusivo del
servidor. Las fases no conceden permisos de comunicaciones.

SQL: database/commercial-contact.sql, database/conversation-actions.sql y
database/commercial-context.sql. Ajustes del flujo: n8n/commercial-conversation.json.
tests/commercial-contact.sql verifica rutas de un solo canal, deduplicación,
registro conversacional, captura de email, score, compras, memoria y STOP dentro
de una transacción con rollback. tests/visual-fixture.cjs permite revisar la UI
local con datos ficticios. Ninguna de estas pruebas envía mensajes reales.

Sigue pendiente conectar el Sheet real con la credencial Sadiet. Los flujos de
integración y los interruptores de envío WhatsApp/Klaviyo siguen desactivados;
no se activan como efecto secundario de esta ampliación.

## Memoria del agente y pedidos de WooCommerce

El primer agente tiene `save_name`, `save_atributos` y `save_tags`, con el patrón
de Dina aplicado exclusivamente a Olivia. Cada herramienta se vincula al
contacto, conversación y lote entrante y exige evidencia literal. Después se
releen los datos antes del segundo agente. El nombre puede corregirse y se pide
si falta, sin convertirlo en requisito ni repetir preguntas ignoradas.

`lead_attributes` guarda atributos tipados por clave. Las listas se combinan y
las correcciones del equipo prevalecen. `lead_states` persiste fase, score,
motivo, temperatura y resumen. El CRM muestra y edita nombre y atributos. Los
registros anteriores alimentan esa memoria. Si las herramientas ya guardaron
los atributos, no se vuelven a escribir desde `commercial_updates`.

Los pedidos se leen con la credencial WooCommerce: páginas de pedidos
modificados, solapamiento de cinco minutos y cursor confirmado solo al terminar.
Se guarda una copia mínima, se cruzan email y teléfono normalizados sin unir
identidades ambiguas y se conservan los estados propios de CTT Express. Se
distinguen compras pagadas, cancelaciones y reembolsos. Los productos habituales
requieren al menos dos pedidos. Ambos agentes y el CRM reciben el historial y
la fecha de sincronización. Importar pedidos no concede permisos de marketing,
no modifica pedidos ni envía comunicaciones.

Las tablas nuevas tienen RLS y acceso de servidor. Los contactos internos de
prueba se excluyen del listado. `node tests/sql-local.cjs` ejecuta los casos en
PostgreSQL local desechable; `node tests/woo-orders.cjs` verifica normalización.

## Comprobaciones

`npm ci`, `npm run build`, `node tests/auth-integration.cjs` y
`node tests/document-routing.cjs`.
La prueba HTTP usa un proveedor local simulado y no manda correos. La prueba de
base de datos tests/document-relations.sql comprueba las relaciones y la consulta
con una transacción que termina en rollback.
