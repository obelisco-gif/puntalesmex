import { NextRequest, NextResponse } from "next/server";
import { isAdmin, sameOrigin } from "../../../../../lib/auth";
import { update, rpc } from "../../../../../lib/supabase";
import { documentInput } from "../../../../../lib/document-input";
import { contactInput, commercialEntryInput, attributeInput } from "../../../../../lib/contact-input";

const editable: Record<string, string[]> = {
  contacts: ["stage", "internal_notes", "manual_tags", "preferences", "assigned_to"],
  conversations: ["status", "priority", "handoff_status", "internal_notes"],
  documents: ["document_type", "title", "content", "source_url", "approval_status", "reviewed_at"]
};

const tables: Record<string, string> = {
  contacts: "contacts",
  conversations: "conversations",
  documents: "product_documents",
  contact_entries: "contact_commercial_entries",
  attributes: "lead_attributes"
};

export async function PATCH(request: NextRequest, context: { params: Promise<{ resource: string; id: string }> }) {
  if (!sameOrigin(request)) return NextResponse.json({ error: "Origen no permitido" }, { status: 403 });
  if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });

  const { resource, id } = await context.params;
  if (!tables[resource]) return NextResponse.json({ error: "Recurso no válido" }, { status: 404 });

  try {
    const incoming = await request.json();
    if (resource === "attributes") {
      const input = attributeInput(incoming);
      return NextResponse.json(await rpc("olivia_save_attribute_crm", { p_contact: id, p_key: input.attribute_key, p_value: input.value_jsonb }));
    }
    if (resource === "contacts" && typeof incoming.automation_blocked === "boolean") {
      if (typeof incoming.expected_updated_at !== "string" || !Number.isFinite(Date.parse(incoming.expected_updated_at))) return NextResponse.json({error:"Actualiza la ficha antes de bloquear el contacto."},{status:400});
      return NextResponse.json(await rpc("olivia_set_contact_block", { p_id: id, p_blocked: incoming.automation_blocked, p_expected_updated_at: incoming.expected_updated_at }));
    }
    if (resource === "contacts") return NextResponse.json(await rpc("olivia_save_contact", { p_id: id, p_input: contactInput(incoming) }));
    if (resource === "contact_entries") return NextResponse.json(await rpc("olivia_save_commercial_entry", { p_contact: id, p_entry: commercialEntryInput(incoming) }));
    if (resource === "documents") {
      const input = documentInput(incoming);
      return NextResponse.json(await rpc("save_olivia_document", { p_document: input, p_id: id }));
    }
    const body = Object.fromEntries(
      editable[resource].filter((key) => key in incoming).map((key) => [key, incoming[key]])
    );

    if (!Object.keys(body).length) return NextResponse.json({ error: "No hay cambios válidos" }, { status: 400 });
    if (resource === "conversations") {
      if (body.status && !["open","paused","closed"].includes(String(body.status))) return NextResponse.json({ error: "Estado no válido" }, { status: 400 });
      if (body.priority && !["low","normal","high","urgent"].includes(String(body.priority))) return NextResponse.json({ error: "Prioridad no válida" }, { status: 400 });
      if (body.handoff_status && !["bot","pending_human","human","resolved"].includes(String(body.handoff_status))) return NextResponse.json({ error: "Atención no válida" }, { status: 400 });
      if (typeof incoming.expected_updated_at !== "string" || !Number.isFinite(Date.parse(incoming.expected_updated_at))) return NextResponse.json({error:"Actualiza la conversación antes de guardar."},{status:400});
      if ("internal_notes" in body && (typeof body.internal_notes !== "string" || body.internal_notes.length > 10000)) return NextResponse.json({error:"Notas no válidas"},{status:400});
      return NextResponse.json(await rpc("olivia_save_conversation",{p_id:id,p_input:{...body,expected_updated_at:incoming.expected_updated_at}}));
    }
    if (resource === "documents" && body.approval_status === "approved" && !body.reviewed_at) {
      body.reviewed_at = new Date().toISOString();
    }
    const result = await update(tables[resource], id, body);
    return NextResponse.json(result[0]);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "No se pudo guardar" }, { status: error instanceof Error && error.message.includes("conversación ha cambiado") ? 409 : 400 });
  }
}
