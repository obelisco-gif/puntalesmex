const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function documentInput(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Documento no válido.");
  const input = value as Record<string, unknown>;
  if (typeof input.title !== "string" || !input.title.trim() || input.title.trim().length > 240) throw new Error("Indica un título de hasta 240 caracteres.");
  if (typeof input.content !== "string" || !input.content.trim() || input.content.trim().length > 100000) throw new Error("Indica el contenido del documento, hasta 100.000 caracteres.");
  if (!Array.isArray(input.catalog_product_ids) || input.catalog_product_ids.length > 100 || !input.catalog_product_ids.every(id => typeof id === "string" && uuid.test(id))) throw new Error("Selecciona productos válidos del catálogo.");
  if (!Array.isArray(input.routing_packages) || input.routing_packages.length < 1 || input.routing_packages.length > 20 || !input.routing_packages.every(topic => typeof topic === "string" && /^[a-z0-9][a-z0-9_-]{0,63}$/.test(topic))) throw new Error("Selecciona entre 1 y 20 temas válidos.");
  const status = input.approval_status || "draft";
  if (!["draft","approved","archived"].includes(String(status))) throw new Error("Estado no válido.");
  const source = typeof input.source_url === "string" ? input.source_url.trim() : "";
  if (source) {
    let url: URL;
    try { url = new URL(source); } catch { throw new Error("La fuente debe ser una dirección web válida."); }
    if (!["http:","https:"].includes(url.protocol)) throw new Error("La fuente debe usar http o https.");
  }
  return { title: input.title.trim(), content: input.content.trim(), source_url: source || null,
    catalog_product_ids: [...new Set(input.catalog_product_ids as string[])],
    routing_packages: [...new Set(input.routing_packages as string[])], approval_status: status };
}
