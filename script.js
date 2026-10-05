// Completa estos valores con información confirmada del cliente antes de producción.
const CONFIG = {
  brandName: "[Marca pendiente]",
  phoneDisplay: "",
  phoneE164: "", // Ejemplo: 525512345678 (solo dígitos)
  whatsappE164: "", // Ejemplo: 525512345678 (solo dígitos)
  whatsappMessage: "Hola, me interesa información sobre puntales para mi obra.",
  ga4MeasurementId: "", // Ejemplo: G-XXXXXXXXXX
  googleAdsId: "" // Ejemplo: AW-XXXXXXXXXX
};

const toast = document.querySelector('.toast');
const notifyPending = () => {
  toast.textContent = 'El dato de contacto todavía está pendiente de configurar.';
  toast.classList.add('show');
  window.setTimeout(() => toast.classList.remove('show'), 3400);
};

document.querySelectorAll('.js-call').forEach((link) => {
  if (CONFIG.phoneE164) {
    link.href = `tel:+${CONFIG.phoneE164}`;
    if (CONFIG.phoneDisplay) link.textContent = link.textContent.includes('Llamar') ? `Llamar: ${CONFIG.phoneDisplay}` : link.textContent;
  } else link.addEventListener('click', (event) => { event.preventDefault(); notifyPending(); });
});

document.querySelectorAll('.js-whatsapp').forEach((link) => {
  if (CONFIG.whatsappE164) {
    link.href = `https://wa.me/${CONFIG.whatsappE164}?text=${encodeURIComponent(CONFIG.whatsappMessage)}`;
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
  } else link.addEventListener('click', (event) => { event.preventDefault(); notifyPending(); });
});

function addScript(src) { const script = document.createElement('script'); script.async = true; script.src = src; document.head.appendChild(script); }
if (CONFIG.ga4MeasurementId) {
  addScript(`https://www.googletagmanager.com/gtag/js?id=${CONFIG.ga4MeasurementId}`);
  window.dataLayer = window.dataLayer || []; function gtag(){ dataLayer.push(arguments); } gtag('js', new Date()); gtag('config', CONFIG.ga4MeasurementId);
}
if (CONFIG.googleAdsId) {
  addScript(`https://www.googletagmanager.com/gtag/js?id=${CONFIG.googleAdsId}`);
  window.dataLayer = window.dataLayer || []; function gtag(){ dataLayer.push(arguments); } gtag('js', new Date()); gtag('config', CONFIG.googleAdsId);
}
document.getElementById('year').textContent = new Date().getFullYear();

