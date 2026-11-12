"use client";

import { useId, useRef, useState } from "react";

type Contact = { id: string; first_name: string | null; phone: string | null; email: string | null; manual_tags: string[]; updated_at: string };
type Save = (resource: string, id: string, body: Record<string, unknown>) => Promise<boolean>;

export function BlockContact({ contact, onSave, disabled = false }: { contact: Contact; onSave: Save; disabled?: boolean }) {
  const dialog = useRef<HTMLDialogElement>(null), title = useId(), description = useId();
  const [busy, setBusy] = useState(false), [error, setError] = useState("");
  const blocked = contact.manual_tags?.includes("crm_blocked");
  const toggle = async () => {
    if (busy) return;
    setBusy(true); setError("");
    try {
      const ok = await onSave("contacts", contact.id, { automation_blocked: !blocked, expected_updated_at: contact.updated_at });
      if (!ok) throw new Error("No se pudo actualizar el bloqueo.");
      dialog.current?.close();
    } catch (e) { setError(e instanceof Error ? e.message : "No se pudo actualizar el bloqueo."); }
    finally { setBusy(false); }
  };
  return <><button type="button" className={blocked ? "secondary" : "delete-contact-button"} disabled={disabled || busy} onClick={() => { setError(""); dialog.current?.showModal(); }}>{blocked ? "Desbloquear contacto" : "Bloquear contacto"}</button>
    <dialog className="delete-contact-dialog" ref={dialog} aria-labelledby={title} aria-describedby={description} onCancel={event => { if (busy) event.preventDefault(); }}>
      <h2 id={title}>{blocked ? "¿Desbloquear contacto?" : "¿Bloquear contacto de Olivia?"}</h2>
      <p><strong>{contact.first_name || "Contacto sin nombre"}</strong><br />{[contact.phone, contact.email].filter(Boolean).join(" · ")}</p>
      {blocked
        ? <p id={description}>El contacto volverá a poder aparecer en los flujos, pero Olivia seguirá con el control humano pausado hasta que lo devuelvas expresamente a Olivia.</p>
        : <p id={description}>Olivia no volverá a responderle. Se conservará el historial, se cancelarán los mensajes pendientes y las nuevas entradas quedarán registradas sin activar a Olivia.</p>}
      {error && <p role="alert">{error}</p>}
      <div className="delete-contact-actions"><button type="button" className="secondary" autoFocus disabled={busy} onClick={() => dialog.current?.close()}>Cancelar</button><button type="button" className={blocked ? "secondary" : "delete-contact-confirm"} disabled={busy} onClick={toggle}>{busy ? "Guardando…" : blocked ? "Desbloquear" : "Bloquear contacto"}</button></div>
    </dialog>
  </>;
}
