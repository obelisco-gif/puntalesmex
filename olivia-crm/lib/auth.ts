import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

export function allowedEmail(email?: string | null) {
  const allowed = (process.env.CRM_ADMIN_EMAILS || "").split(",").map((value) => value.trim().toLowerCase()).filter(Boolean);
  return Boolean(email && allowed.includes(email.trim().toLowerCase()));
}

export async function authClient() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) throw new Error("Falta configurar el acceso de Supabase.");
  const store = await cookies();
  return createServerClient(url, key, {
    cookieOptions: { httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "lax", path: "/" },
    global: { fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(12000), cache: "no-store" }) },
    cookies: {
      getAll: () => store.getAll(),
      setAll: (values) => values.forEach(({ name, value, options }) => store.set(name, value, options)),
    },
  });
}

export async function adminUser() {
  try {
    const supabase = await authClient();
    const { data: { user }, error } = await supabase.auth.getUser();
    if (error || !user || user.is_anonymous || !user.email_confirmed_at || !allowedEmail(user.email)) return null;
    return user;
  } catch {
    return null;
  }
}

export async function isAdmin() { return Boolean(await adminUser()); }

export function sameOrigin(request: Request) {
  const origin = request.headers.get("origin");
  return !origin || origin === new URL(request.url).origin;
}

export async function clearSession() {
  const supabase = await authClient();
  await supabase.auth.signOut({ scope: "local" });
  (await cookies()).delete("olivia_crm_session");
}
