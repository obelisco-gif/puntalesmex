import { NextResponse } from "next/server";
import { allowedEmail, authClient, sameOrigin } from "../../../../lib/auth";

export async function POST(request: Request) {
  if (!sameOrigin(request)) return NextResponse.json({ error: "Origen no permitido." }, { status: 403 });
  try {
    const input = await request.json();
    const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
    const message = "Si tu cuenta existe y tiene acceso, recibirás un enlace para recuperar tu contraseña. Revisa también la carpeta de spam.";
    if (!allowedEmail(email)) return NextResponse.json({ message });
    const site = process.env.CRM_SITE_URL;
    if (!site) throw new Error("Missing site URL");
    const redirect = new URL("/auth/callback", site);
    redirect.searchParams.set("next", "/reset-password");
    const supabase = await authClient();
    // Provisioning is managed in Supabase Auth, never by a public sign-up route.
    const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: redirect.toString() });
    if (error) return NextResponse.json({ error: "No se pudo enviar el enlace. Espera unos minutos y vuelve a intentarlo; si continúa, contacta con el administrador." }, { status: 503 });
    return NextResponse.json({ message }, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    return NextResponse.json({ error: "No se pudo solicitar el enlace de acceso." }, { status: 503 });
  }
}
