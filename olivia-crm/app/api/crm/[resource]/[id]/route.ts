import { NextRequest, NextResponse } from "next/server";
import { isAdmin, sameOrigin } from "../../../../../lib/auth";
import { update, rpc } from "../../../../../lib/supabase";
import { documentInput } from "../../../../../lib/document-input";

const editable: Record<string, string[]> = {
  contacts: ["stage", "internal_notes", "manual_tags", "preferences", "assigned_to"],
  conversations: ["status", "priority", "handoff_status", "internal_notes"],
  documents: ["document_type", "title", "content", "source_url", "approval_status", "reviewed_at"]
};

const tables: Record<string, string> = {
  contacts: "contacts",
  conversations: "conversations",
  documents: "product_documents"
};

export async function PATCH(request: NextRequest, context: { params: Promise<{ resource: string; id: string }> }) {
  if (!sameOrigin(request)) return NextResponse.json({ error: "Origen no permitido" }, { status: 403 });
  if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });

  const { resource, id } = await context.params;
  if (!tables[resource]) return NextResponse.json({ error: "Recurso no válido" }, { status: 404 });

  try {
    const incoming = await request.json();
    if (resource === "documents") {
      const input = documentInput(incoming);
      return NextResponse.json(await rpc("save_olivia_document", { p_document: input, p_id: id }));
    }
    const body = Object.fromEntries(
      editable[resource].filter((key) => key in incoming).map((key) => [key, incoming[key]])
    );

    if (!Object.keys(body).length) return NextResponse.json({ error: "No hay cambios válidos" }, { status: 400 });
    if (resource === "documents" && body.approval_status === "approved" && !body.reviewed_at) {
      body.reviewed_at = new Date().toISOString();
    }
    const result = await update(tables[resource], id, body);
    return NextResponse.json(result[0]);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "No se pudo guardar" }, { status: resource === "documents" ? 400 : 500 });
  }
}
