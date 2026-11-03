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

## Validación

`npm ci`, `npm run build` y `node tests/auth-integration.cjs`.
La prueba HTTP usa un proveedor Auth local simulado y no manda correos.
