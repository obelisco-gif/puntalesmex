const baseUrl = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

function config() {
  if (!baseUrl || !serviceKey) throw new Error("Falta configurar Supabase en Vercel.");
  return { baseUrl: baseUrl.replace(/\/$/, ""), serviceKey };
}

export async function select<T>(table: string, query: string): Promise<T[]> {
  const { baseUrl, serviceKey } = config();
  const response = await fetch(baseUrl + "/rest/v1/" + table + "?" + query, {
    headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey },
    cache: "no-store"
  });
  if (!response.ok) throw new Error("No se pudo leer " + table);
  return response.json();
}

export async function update<T>(table: string, id: string, body: object): Promise<T[]> {
  const { baseUrl, serviceKey } = config();
  const response = await fetch(baseUrl + "/rest/v1/" + table + "?id=eq." + encodeURIComponent(id), {
    method: "PATCH",
    headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, "content-type": "application/json", Prefer: "return=representation" },
    body: JSON.stringify(body)
  });
  if (!response.ok) throw new Error("No se pudo actualizar " + table);
  return response.json();
}
