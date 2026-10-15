import { NextResponse } from "next/server";
import { isAdmin } from "../../../../lib/auth";
import { update } from "../../../../lib/supabase";

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });
  const { id } = await params;
  const body = await request.json();
  const internal_notes = typeof body.internal_notes === "string" ? body.internal_notes.slice(0, 5000) : null;
  const manual_tags = Array.isArray(body.manual_tags) ? body.manual_tags.map(String).map((tag: string) => tag.trim()).filter(Boolean).slice(0, 20) : [];
  try {
    const result = await update("catalog_products", id, { internal_notes, manual_tags, internal_updated_at: new Date().toISOString() });
    return NextResponse.json(result[0]);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Error al guardar" }, { status: 500 });
  }
}
