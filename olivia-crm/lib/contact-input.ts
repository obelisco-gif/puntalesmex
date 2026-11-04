export const contactStages = ["new", "engaged", "qualified", "recommended", "purchase_intent", "customer", "on_hold", "lost", "unsubscribed"];

export function contactInput(input: Record<string, unknown>) {
  if (!contactStages.includes(String(input.stage))) throw new Error("Fase no válida.");
  if (!Array.isArray(input.manual_tags) || input.manual_tags.length > 50 || input.manual_tags.some(t => typeof t !== "string" || t.length > 100)) throw new Error("Etiquetas no válidas.");
  if (!input.expected_updated_at || !Number.isFinite(Date.parse(String(input.expected_updated_at)))) throw new Error("Actualiza la ficha antes de guardar.");
  const profile = input.commercial as Record<string, unknown>;
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) throw new Error("Atributos no válidos.");
  for (const key of ["tastes", "objections", "buying_horizon"]) if (typeof profile[key] !== "string" || String(profile[key]).length > (key === "buying_horizon" ? 500 : 2000)) throw new Error("Revisa los atributos comerciales.");
  if (profile.score_override !== null && (!Number.isInteger(profile.score_override) || Number(profile.score_override) < 0 || Number(profile.score_override) > 100)) throw new Error("El score debe estar entre 0 y 100.");
  return { stage: input.stage, internal_notes: String(input.internal_notes ?? "").slice(0, 10000), assigned_to: String(input.assigned_to ?? "").slice(0, 100), manual_tags: input.manual_tags, expected_updated_at: input.expected_updated_at,
    commercial: Object.fromEntries(["tastes", "objections", "buying_horizon", "score_override"].map(k => [k, profile[k]])) };
}

export function commercialEntryInput(input: Record<string, unknown>) {
  const kind = String(input.kind);
  const status = String(input.status);
  if (!["interest", "avoid", "order_inquiry", "purchase"].includes(kind)) throw new Error("Tipo de registro no válido.");
  const statuses = kind === "purchase" ? ["declared", "confirmed", "cancelled"] : ["open", "resolved", "cancelled"];
  if (!statuses.includes(status)) throw new Error("Estado no válido para este registro.");
  const details = String(input.details ?? "").trim(), reference = String(input.reference ?? "").trim();
  if (!details || details.length > 2000 || reference.length > 120 || (kind === "purchase" && !reference)) throw new Error("Añade el detalle y, para compras, una referencia de pedido.");
  const amount = input.amount === null || input.amount === "" ? null : Number(input.amount);
  if (amount !== null && (kind !== "purchase" || !Number.isFinite(amount) || amount < 0 || amount > 9999999999.99 || Math.abs(Math.round(amount * 100) - amount * 100) > 0.00001)) throw new Error("Importe no válido.");
  const quantity = input.quantity === null || input.quantity === "" ? null : Number(input.quantity);
  if (quantity !== null && (!Number.isInteger(quantity) || quantity < 1 || quantity > 10000)) throw new Error("Cantidad no válida.");
  const productId = input.product_id || null;
  if (productId && !/^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i.test(String(productId))) throw new Error("Producto no válido.");
  const date = String(input.occurred_on ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(Date.parse(date))) throw new Error("Fecha no válida.");
  return { kind, status, details, reference, product_id: productId, amount, quantity, occurred_on: date, currency: "EUR" };
}
