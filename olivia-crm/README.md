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

Los ajustes de n8n están exportados en n8n/document-routing.json y preparados en
el borrador del flujo de conversación. Su publicación se gestiona por separado.
La versión antigua recibe también los temas y relaciones en su contexto.

## Validación

`npm ci`, `npm run build`, `node tests/auth-integration.cjs` y
`node tests/document-routing.cjs`.
La prueba HTTP usa un proveedor local simulado y no manda correos. La prueba de
base de datos tests/document-relations.sql comprueba las relaciones y la consulta
con una transacción que termina en rollback.
