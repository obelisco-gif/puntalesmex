# Selección de documentación entre los agentes de Olivia

Arquitectura corregida el 6 de noviembre de 2026.

Ambos agentes reciben el contexto real del mismo contacto: conversación, atributos, intereses, rechazos, cualificación, fase, score, etiquetas, permisos, estado del email y últimos pedidos. Después de las herramientas y acciones se releen esos datos antes de redactar.

El primer agente recibe las pautas básicas de comunicación, sus reglas propias de memoria y cualificación y un índice descriptivo de la biblioteca. El índice contiene ID, título, categoría, temas y productos vinculados; no copia el contenido de los documentos. El primer agente guarda los hechos nuevos y emite selected_document_ids y product_ids.

El segundo recibe la decisión validada, el contexto actualizado, los documentos concretos seleccionados por ID y los productos elegidos con sus variantes. La identidad, tono e idioma marcados como always se inyectan siempre y una sola vez. No recibe las reglas del primer agente ni el índice de toda la biblioteca.

La campaña Black Friday, inscripción, pedidos, preparación, STOP y derivación son seleccionables; no se cargan en bloque. Los temas knowledge_packages se mantienen como clasificación, pero no sustituyen la selección por ID. Las guías vinculadas a productos solo entran si corresponde el producto seleccionado. Documentos internos, borradores o archivados se rechazan incluso si se intenta seleccionarlos.

Clasificación actual: always = identidad tono e idioma; orchestrator = ficha memoria cualificación y selección documental; black_friday = condiciones de campaña; early_access = inscripción y canales; opt_out = bajas; handoff/support/safety = atención del equipo. Los demás documentos conservan sus temas y vínculos a productos. Las reglas continúan editables en el CRM.

Verificación: suite SQL con contactos ficticios, conservación del contexto en ambos agentes, índice sin cuerpo documental, selección exacta de IDs, exclusión de documentos de otro producto, campaña no automática, edición inmediata, archivado, permisos y pruebas del validador de decisiones. No se han enviado mensajes de prueba ni se ha modificado Dina.

El documento flexible-policies.md y su snapshot registran la reorganización anterior; esta arquitectura la sustituye.
