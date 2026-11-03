import { NextResponse } from "next/server";
import { allowedEmail, authClient, clearSession, sameOrigin } from "../../../lib/auth";

export async function POST(request: Request) {
  if (!sameOrigin(request)) return NextResponse.json({ error: "Origen no permitido." }, { status: 403 });
  try {
    const input = await request.json();
    const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
    const password = typeof input.password === "string" ? input.password : "";
    if (!email || !password || !allowedEmail(email)) return NextResponse.json({ error: "Email o contraseña incorrectos." }, { status: 401 });
    const supabase = await authClient();
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.user?.email_confirmed_at || !allowedEmail(data.user.email)) {
      await supabase.auth.signOut({ scope: "local" });
      return NextResponse.json({ error: "Email o contraseña incorrectos." }, { status: 401 });
    }
    return NextResponse.json({ ok: true }, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    return NextResponse.json({ error: "No se pudo iniciar sesión. Inténtalo de nuevo." }, { status: 503 });
  }
}

export async function DELETE(request: Request) {
  if (!sameOrigin(request)) return NextResponse.json({ error: "Origen no permitido." }, { status: 403 });
  await clearSession();
  return NextResponse.json({ ok: true });
}
