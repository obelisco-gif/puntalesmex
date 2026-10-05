# Puntales México — landing de captación

Landing estática, rápida y preparada para Vercel para captar prospectos de puntales para construcción en México. Está diseñada para conversión mediante WhatsApp y llamada: no incluye formulario.

## Configuración antes de publicar

En [`script.js`](./script.js), sustituye los valores de `CONFIG`:

- `brandName`
- `phoneDisplay` y `phoneE164`
- `whatsappE164`
- `whatsappMessage`
- `ga4MeasurementId`
- `googleAdsId`

Mientras estos valores estén vacíos, los CTA muestran un aviso y no intentan contactar a un número ficticio.

También actualiza el dominio canónico, las imágenes Open Graph y el texto de cobertura en [`index.html`](./index.html).

## Desarrollo y despliegue

No hay dependencias ni compilación: abre `index.html` con un servidor estático local.

Para Vercel:

1. Sube este repositorio a GitHub.
2. Importa el repositorio en Vercel.
3. Configura el dominio cuando esté disponible.
4. Completa los datos pendientes antes de producción.

`vercel.json` fuerza cabeceras seguras y caché de recursos estáticos.

## Fotografías

Las fotografías proporcionadas están incluidas para la muestra en `assets/images/`. El cliente confirmó la autorización para su uso público. Pueden sustituirse o complementarse con imágenes finales si fuera necesario.

## Pendientes del cliente

Marca, teléfono, WhatsApp, cobertura real, catálogo, condiciones comerciales, logotipo, fotografías propias, dominio, aviso de privacidad e IDs de GA4/Google Ads.
