# Variantes del catálogo de Olivia

Actualizado el 5 de noviembre de 2026. Solo afecta a Olivia / Sadiet.

El flujo existente «Olivia · Sincronizar catálogo de WooCommerce» conserva su ejecución cada hora. Primero actualiza los productos publicados y después consulta todas las páginas de `/products/{id}/variations` para los productos variables. Se usa la credencial de lectura de WooCommerce existente. Las peticiones se limitan a una por lote, con una pausa de 500 ms y hasta tres intentos si falla la tienda.

Cada variante conserva su ID de WooCommerce, SKU, atributos (cantidad, formato, sabor o modelo), precio, precio habitual y rebajado, comprabilidad, stock, cantidad disponible, enlace y fecha de sincronización. Cero unidades y cantidad desconocida son estados distintos.

El guardado comprueba que se han recibido exactamente los IDs anunciados por el producto padre. Solo una descarga completa sustituye la instantánea anterior y desactiva variantes que hayan desaparecido. Las descargas incompletas se rechazan; una ejecución antigua no sustituye otra más reciente. Si la descarga falla, se conserva la información anterior y queda indicada una actualización pendiente. Las anotaciones y etiquetas manuales del producto se conservan.

En Catálogo, cada producto variable muestra un desplegable «Variantes» con opciones, precio y disponibilidad independientes. La consulta está protegida por la sesión de administrador; las tablas y funciones de sincronización no se exponen al navegador.

El primer agente recibe el resumen del padre, sus atributos y el número de variantes. Selecciona el ID del producto padre. El segundo recibe el detalle de sus variantes publicadas y activas junto con la documentación seleccionada. Sus instrucciones exigen usar el precio y el stock de la opción concreta, pedir aclaración si falta la combinación y evitar presentar una rebaja de WooCommerce como promoción Black Friday confirmada. La disponibilidad refleja la última sincronización, no una reserva de stock.

Verificación real: ejecución 308046 completada; 46 productos principales, 27 productos variables completos y 123 variantes activas. Se comprobaron paginación de 101 variantes, asociación a sus padres, descargas incompletas, reintentos, stock cero/desconocido, retirada de variantes, conservación de notas y acceso privado. Vista del CRM comprobada localmente con datos ficticios y compilación de producción correcta.

Fuentes de implementación: `database/catalog-variations.sql`, `database/catalog-parent-sync.sql`, `database/catalog-variations-context.sql`, `n8n/catalog-variations.json` y `n8n/catalog-variations-normalize.cjs`.
