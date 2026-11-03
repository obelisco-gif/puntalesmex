"use client";

import { FormEvent, useState } from "react";

export default function ResetPassword() {
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    if (form.get("password") !== form.get("confirm")) return setNotice("Las contraseñas no coinciden.");
    setBusy(true); setNotice("");
    try {
      const res = await fetch("/api/auth/password", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ password: form.get("password") }) });
      const body = await res.json();
      if (!res.ok) { setNotice(body.error || "No se pudo guardar la contraseña."); return; }
      window.location.assign("/");
    } catch { setNotice("No se pudo conectar. Inténtalo de nuevo."); }
    finally { setBusy(false); }
  }
  return <main className="login-shell"><section className="login-card"><p className="eyebrow">SADIET · OLIVIA</p><h1>Tu contraseña</h1><p>Crea una contraseña personal de al menos 12 caracteres para acceder al CRM.</p><form onSubmit={save}><label>Nueva contraseña<input name="password" type="password" autoComplete="new-password" required minLength={12} maxLength={128} /></label><label>Repetir contraseña<input name="confirm" type="password" autoComplete="new-password" required minLength={12} maxLength={128} /></label><button disabled={busy}>{busy ? "Guardando…" : "Guardar contraseña"}</button></form>{notice && <p className="notice" role="alert">{notice}</p>}<p><a href="/">Volver al acceso</a></p></section></main>;
}
