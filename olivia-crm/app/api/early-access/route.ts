import { NextResponse } from "next/server";
import { isAdmin } from "../../../lib/auth";
import { count } from "../../../lib/supabase";

export async function GET() {
  if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });
  const tagged = "select=id&manual_tags=cs.%7Bbf2026_early_access%7D";
  try {
    const [total, email, phone, both] = await Promise.all([
      count("contacts", tagged),
      count("contacts", tagged + "&email=not.is.null&email=neq."),
      count("contacts", tagged + "&phone=not.is.null&phone=neq."),
      count("contacts", tagged + "&email=not.is.null&email=neq.&phone=not.is.null&phone=neq.")
    ]);
    return NextResponse.json({ total, email, phone, both });
  } catch {
    return NextResponse.json({ error: "No se pudieron cargar las estadísticas." }, { status: 500 });
  }
}
