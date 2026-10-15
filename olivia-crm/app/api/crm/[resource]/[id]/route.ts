import { NextRequest, NextResponse } from "next/server";
import { isAdmin } from "../../../../../lib/auth";
import { update } from "../../../../../lib/supabase";

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
  if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });

  const { resource, id } = await context.params;
  if (!tables[resource]) return NextResponse.json({ error: "Recurso no válido" }, { status: 404 });

  try {
    const incoming = await request.json();
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
    return NextResponse.json({ error: error instanceof Error ? error.message : "No se pudo guardar" }, { status: 500 });
  }
}