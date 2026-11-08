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

export async function count(table: string, query: string): Promise<number> {
  const { baseUrl } = config();
  const response = await fetch(baseUrl + "/rest/v1/" + table + "?" + query, {
    method: "HEAD", headers: headers({ Prefer: "count=exact" }), cache: "no-store"
  });
  if (!response.ok) throw new Error("No se pudo contar " + table);
  const total = response.headers.get("content-range")?.split("/").pop();
  if (!total || !/^\d+$/.test(total)) throw new Error("No se pudo obtener el total de " + table);
  return Number(total);
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

export async function rpc<T>(name: string, body: object): Promise<T> {
  const { baseUrl } = config();
  const response = await fetch(baseUrl + "/rest/v1/rpc/" + name, {
    method: "POST", headers: headers({ "content-type": "application/json" }),
    body: JSON.stringify(body), cache: "no-store"
  });
  if (!response.ok) {
    const result = await response.json().catch(() => ({}));
    if (name === "olivia_delete_contact") {
      const message=String(result.message||"");
      if (["El contacto ha cambiado. Actualiza la ficha antes de eliminar.","Hay envíos o integraciones en curso. Espera a que terminen antes de eliminar."].includes(message)) throw new Error(message);
      throw new Error("No se pudo eliminar el perfil. Actualiza la ficha y vuelve a intentarlo.");
    }
    if (["olivia_save_conversation","olivia_manual_reply"].includes(name) && String(result.message).includes("conversación ha cambiado")) throw new Error("La conversación ha cambiado. Actualízala antes de guardar.");
    if (name === "olivia_save_handoff" && String(result.message).includes("derivación ha cambiado")) throw new Error("La derivación ha cambiado. Actualiza antes de guardar.");
    if (name === "olivia_manual_reply") {
      const message=String(result.message||"");
      if (["Esta conversación no tiene WhatsApp disponible","Este contacto ha solicitado la baja de WhatsApp","La ventana de respuesta de WhatsApp está cerrada. Es necesario que el contacto vuelva a escribir","Identificador de envío ya utilizado"].includes(message)) throw new Error(message);
    }
    if (name === "olivia_save_contact" && String(result.message).includes("contacto ha cambiado")) throw new Error("El contacto ha cambiado. Actualiza la ficha antes de guardar.");
    throw new Error("No se pudo guardar. Revisa los datos, actualiza la ficha y vuelve a intentarlo.");
  }
  return response.json();
}
