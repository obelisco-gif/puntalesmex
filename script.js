// Completa estos valores con información confirmada del cliente antes de producción.
const CONFIG = {
  brandName: "Operadora OYC",
  whatsappE164: "529999972368", // México: 52 + número de 10 dígitos
  whatsappMessage: "Hola, me interesa información sobre puntales para mi obra.",
  ga4MeasurementId: "", // Ejemplo: G-XXXXXXXXXX
  googleAdsId: "" // Ejemplo: AW-XXXXXXXXXX
};

const toast = document.querySelector('.toast');
const notifyPending = () => {
  toast.textContent = 'WhatsApp todavía está pendiente de configurar.';
  toast.classList.add('show');
  window.setTimeout(() => toast.classList.remove('show'), 3400);
};

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

const heroVisual = document.querySelector('.hero-visual');
const heroParallaxAllowed = window.matchMedia('(min-width: 761px) and (prefers-reduced-motion: no-preference)');
if (heroVisual && heroParallaxAllowed.matches) {
  let pendingFrame = false;
  const updateHeroParallax = () => {
    const rect = heroVisual.getBoundingClientRect();
    const viewportCenter = window.innerHeight / 2;
    const visualCenter = rect.top + (rect.height / 2);
    const progress = Math.max(-1, Math.min(1, (visualCenter - viewportCenter) / (viewportCenter + (rect.height / 2))));
    heroVisual.style.setProperty('--hero-parallax', `${Math.round(progress * -22)}px`);
    pendingFrame = false;
  };
  const requestHeroParallax = () => {
    if (!pendingFrame) {
      pendingFrame = true;
      window.requestAnimationFrame(updateHeroParallax);
    }
  };
  window.addEventListener('scroll', requestHeroParallax, { passive: true });
  window.addEventListener('resize', requestHeroParallax);
  requestHeroParallax();
}

