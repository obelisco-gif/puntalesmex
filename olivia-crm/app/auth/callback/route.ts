import { NextResponse } from "next/server";
import type { EmailOtpType } from "@supabase/supabase-js";
import { allowedEmail, authClient } from "../../../lib/auth";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const tokenHash = url.searchParams.get("token_hash");
  const type = url.searchParams.get("type");
  const supabase = await authClient();
  let ok = false;
  if (code) {
    const { data, error } = await supabase.auth.exchangeCodeForSession(code);
    ok = !error && allowedEmail(data.user?.email) && Boolean(data.user?.email_confirmed_at);
  } else if (tokenHash && ["email", "recovery", "invite", "signup", "magiclink"].includes(type || "")) {
    const { data, error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: type as EmailOtpType });
    ok = !error && allowedEmail(data.user?.email) && Boolean(data.user?.email_confirmed_at);
  }
  if (!ok) {
    await supabase.auth.signOut({ scope: "local" });
    return NextResponse.redirect(new URL("/?auth_error=expired", url.origin));
  }
  // Only fixed destinations are accepted, never a caller-supplied external URL.
  const next = url.searchParams.get("next") === "/reset-password" ? "/reset-password" : "/";
  const response = NextResponse.redirect(new URL(next, url.origin));
  response.headers.set("Cache-Control", "private, no-store");
  response.headers.set("Referrer-Policy", "no-referrer");
  return response;
}
