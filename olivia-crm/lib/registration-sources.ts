import { select } from "./supabase";

export type RegistrationSource = "meta_lead_form" | "landing_form";
type Event = { contact_id: string; source: RegistrationSource };

export async function registrationSources(ids: string[]): Promise<Record<string, RegistrationSource[]>> {
  const unique = [...new Set(ids)];
  if (!unique.length) return {};
  if (unique.some(id => !/^[0-9a-f-]{36}$/i.test(id))) throw new Error("Identificador no válido");
  const sources: Record<string, RegistrationSource[]> = {};
  for (let offset = 0; ; offset += 1000) {
    const events = await select<Event>("contact_events", `select=contact_id,source&event_type=eq.early_access_registered&source=in.(meta_lead_form,landing_form)&contact_id=in.(${unique.join(",")})&order=id.asc&limit=1000&offset=${offset}`);
    for (const event of events) {
      const list = sources[event.contact_id] ||= [];
      if (!list.includes(event.source)) list.push(event.source);
    }
    if (events.length < 1000) break;
  }
  return sources;
}
