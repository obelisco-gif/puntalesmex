import { NextRequest, NextResponse } from "next/server";
import { isAdmin } from "../../../lib/auth";
import { insert } from "../../../lib/supabase";

export async function POST(request: NextRequest) {
  if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });
  try {
    const input = await request.json();
    if (!input.title?.trim() || !input.content?.trim()) {
      return NextResponse.json({ error: "Indica un título y el contenido." }, { status: 400 });
    }
    const result = await insert("product_documents", {
      title: input.title.trim(),
      content: input.content.trim(),
      document_type: input.document_type || "commercial",
      source_url: input.source_url?.trim() || null,
      approval_status: "draft"
    });
    return NextResponse.json(result[0], { status: 201 });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "No se pudo crear el documento" }, { status: 500 });
  }
}