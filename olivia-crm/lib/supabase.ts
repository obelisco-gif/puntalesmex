const baseUrl = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

function config() {
  if (!baseUrl || !serviceKey) throw new Error("Falta configurar Supabase en Vercel.");
  return { baseUrl: baseUrl.replace(/\/$/, ""), serviceKey };
}

function headers(extra: Record<string, string> = {}) {
  const { serviceKey } = config();
  return { apikey: serviceKey, Authorization: "Bearer " + serviceKey, ...extra };
}

export async function select<T>(table: string, query: string): Promise<T[]> {
  const { baseUrl } = config();
  const response = await fetch(baseUrl + "/rest/v1/" + table + "?" + query, {
    headers: headers(),
    cache: "no-store"
  });
  if (!response.ok) throw new Error("No se pudo leer " + table);
  return response.json();
}

export async function update<T>(table: string, id: string, body: object): Promise<T[]> {
  const { baseUrl } = config();
  const response = await fetch(baseUrl + "/rest/v1/" + table + "?id=eq." + encodeURIComponent(id), {
    method: "PATCH",
    headers: headers({ "content-type": "application/json", Prefer: "return=representation" }),
    body: JSON.stringify(body)
  });
  if (!response.ok) throw new Error("No se pudo actualizar " + table);
  return response.json();
}

export async function insert<T>(table: string, body: object): Promise<T[]> {
  const { baseUrl } = config();
  const response = await fetch(baseUrl + "/rest/v1/" + table, {
    method: "POST",
    headers: headers({ "content-type": "application/json", Prefer: "return=representation" }),
    body: JSON.stringify(body)
  });
  if (!response.ok) throw new Error("No se pudo guardar en " + table);
  return response.json();
}
