import { NextResponse } from "next/server";
import { adminUser, authClient, sameOrigin } from "../../../../lib/auth";

export async function POST(request: Request) {
  if (!sameOrigin(request)) return NextResponse.json({ error: "Origen no permitido." }, { status: 403 });
  if (!(await adminUser())) return NextResponse.json({ error: "El enlace ha caducado. Solicita otro desde la pantalla de acceso." }, { status: 401 });
  try {
    const input = await request.json();
    if (typeof input.password !== "string" || input.password.length < 12 || input.password.length > 128) {
      return NextResponse.json({ error: "Usa una contraseña de entre 12 y 128 caracteres." }, { status: 400 });
    }
    const supabase = await authClient();
    const { error } = await supabase.auth.updateUser({ password: input.password });
    if (error) return NextResponse.json({ error: "No se pudo guardar. Prueba con otra contraseña o solicita un enlace nuevo." }, { status: 400 });
    return NextResponse.json({ ok: true }, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    return NextResponse.json({ error: "No se pudo actualizar la contraseña." }, { status: 503 });
  }
}
