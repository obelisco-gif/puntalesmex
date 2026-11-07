import { NextRequest, NextResponse } from "next/server";
import { isAdmin, sameOrigin } from "../../../lib/auth";
import { rpc } from "../../../lib/supabase";
import { documentInput } from "../../../lib/document-input";

export async function POST(request: NextRequest) {
  if (!sameOrigin(request)) return NextResponse.json({ error: "Origen no permitido" }, { status: 403 });
  if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });
  try {
    const input = documentInput(await request.json());
    const result = await rpc("save_olivia_document", { p_document: input, p_id: null });
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "No se pudo crear el documento" }, { status: 400 });
  }
}
