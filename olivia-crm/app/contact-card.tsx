"use client";
import { FormEvent, useState } from "react";
import { Attributes, type AttributeRecord } from "./attributes";
import { PurchaseHistoryCard, type PurchaseHistory } from "./purchase-history";

type Entry = { id: string; kind: string; product_id: string | null; reference: string; details: string; status: string; amount: number | null; currency: string; quantity: number | null; occurred_on: string; source: string; evidence: string | null };
type Profile = { tastes?: string; objections?: string; buying_horizon?: string; score_override?: number | null };
export type Contact = { id: string; first_name: string | null; email: string | null; phone: string | null; stage: string; source: string | null; manual_tags: string[]; internal_notes: string | null; preferences: { commercial?: Profile; olivia?: { summary?: string; pending_question?: string; temperature?: string } }; assigned_to: string | null; updated_at: string; commercial_entries: Entry[]; attribute_records?: AttributeRecord[]; purchase_history?: PurchaseHistory; score: { value: number; automatic: number; manual: boolean; reasons: { reason: string; points: number }[] } };
type Product = { id: string; name: string };
type Save = (resource: string, id: string, body: Record<string, unknown>) => Promise<boolean>;
export const stages = [["new","Nuevo"],["engaged","En conversación"],["qualified","Necesidad identificada"],["recommended","Recomendación realizada"],["purchase_intent","Intención de compra"],["customer","Cliente"],["on_hold","En seguimiento"],["lost","Sin interés actual"],["unsubscribed","Baja comercial"]];
const kinds: Record<string,string> = { interest: "Le interesa", avoid: "Prefiere evitar", order_inquiry: "Consulta de pedido", purchase: "Compra" };
const statuses: Record<string,string> = { open: "Abierto", resolved: "Resuelto", declared: "Declarada, sin verificar", confirmed: "Confirmada", cancelled: "Cancelado" };

export function ContactCard({ contact, products, onSave, compact = false }: { contact: Contact; products: Product[]; onSave: Save; compact?: boolean }) {
  const p = contact.preferences?.commercial || {};
  const [stage, setStage] = useState(contact.stage), [notes, setNotes] = useState(contact.internal_notes || ""), [tags, setTags] = useState(contact.manual_tags?.join(", ") || ""), [assigned, setAssigned] = useState(contact.assigned_to || "");
  const [tastes, setTastes] = useState(p.tastes || ""), [objections, setObjections] = useState(p.objections || ""), [horizon, setHorizon] = useState(p.buying_horizon || ""), [score, setScore] = useState(p.score_override == null ? "" : String(p.score_override));
  const [busy, setBusy] = useState(false);
  const [name, setName] = useState(contact.first_name || "");
  const entries = contact.commercial_entries || [];
  const purchases = entries.filter(e => e.kind === "purchase" && e.status === "confirmed");
  const save = async (event: FormEvent) => {
    event.preventDefault(); setBusy(true);
    try { await onSave("contacts", contact.id, { first_name: name, stage, internal_notes: notes, assigned_to: assigned, manual_tags: tags.split(",").map(t => t.trim()).filter(Boolean), expected_updated_at: contact.updated_at, commercial: { tastes, objections, buying_horizon: horizon, score_override: score === "" ? null : Number(score) } }); }
    finally { setBusy(false); }
  };
  return <article className="record-card contact-detail">
    <div className="record-heading"><div><h2>{contact.first_name || "Sin nombre"}</h2><p>{contact.email || "Sin email"} · {contact.phone || "Sin WhatsApp"}</p><small>{contact.source || "Origen sin definir"}</small></div><div className="contact-score"><strong>{contact.score?.value ?? 0}<small>/100</small></strong><span>{contact.score?.manual ? "Score manual" : "Score automático"}</span></div></div>
    <div className="chips"><span>{stages.find(s => s[0] === contact.stage)?.[1] || contact.stage}</span>{contact.manual_tags.includes("bf2026_early_access") && <span>Early Access inscrito</span>}<span>{purchases.length} compras confirmadas · {purchases.reduce((sum,e) => sum + Number(e.amount || 0),0).toLocaleString("es-ES",{style:"currency",currency:"EUR"})}</span></div>
    <details><summary>Cómo se calcula el score</summary><p>Indica interés comercial actual de 0 a 100, no probabilidad de compra. Olivia valora el contexto y guarda el motivo. Sin una valoración reciente se usa el cálculo por fase y hechos confirmados. Tu ajuste manual tiene prioridad.</p><ul>{contact.score?.reasons.map((r,i) => <li key={i}>{r.reason}: {r.points} puntos</li>)}</ul>{contact.score?.manual && <p>Automático: {contact.score.automatic}. Se aplica tu ajuste manual.</p>}</details>
    {compact && <Attributes contactId={contact.id} records={contact.attribute_records || []} onSave={onSave} />}
    <details open={!compact} className="contact-editor"><summary>Editar ficha comercial</summary><form onSubmit={save}>
      <label>Nombre confirmado<input maxLength={100} value={name} onChange={e=>setName(e.target.value)} /></label>
      <div className="form-row"><label>Fase<select value={stage} onChange={e => setStage(e.target.value)}>{stages.map(([v,l]) => <option key={v} value={v}>{l}</option>)}</select></label><label>Responsable<input maxLength={100} value={assigned} onChange={e => setAssigned(e.target.value)} /></label><label>Ajuste manual del score<input type="number" min="0" max="100" step="1" value={score} onChange={e => setScore(e.target.value)} placeholder="Vacío = automático" /></label></div>
      <div className="form-row"><label>Gustos, sabores y formatos<textarea maxLength={2000} value={tastes} onChange={e => setTastes(e.target.value)} /></label><label>Objeciones y reticencias<textarea maxLength={2000} value={objections} onChange={e => setObjections(e.target.value)} /></label></div>
      <label>Cuándo quiere comprar / seguimiento<input maxLength={500} value={horizon} onChange={e => setHorizon(e.target.value)} /></label>
      <label>Notas internas<textarea maxLength={10000} value={notes} onChange={e => setNotes(e.target.value)} /></label><label>Etiquetas<input value={tags} onChange={e => setTags(e.target.value)} /></label><button disabled={busy}>{busy ? "Guardando…" : "Guardar ficha"}</button>
    </form></details>
    {!compact && <Attributes contactId={contact.id} records={contact.attribute_records || []} onSave={onSave} />}
    <PurchaseHistoryCard history={contact.purchase_history} />
    {contact.preferences?.olivia?.summary && <section className="contact-memory"><h3>Contexto de Olivia</h3><p>{contact.preferences.olivia.summary}</p>{contact.preferences.olivia.pending_question && <p><b>Pendiente:</b> {contact.preferences.olivia.pending_question}</p>}</section>}
    <section><h3>Productos, pedidos y compras</h3>{entries.length ? <div className="commercial-entries">{entries.map(e => <div key={e.id} className="commercial-entry"><div><b>{kinds[e.kind]}</b><span>{statuses[e.status] || e.status}</span></div><p>{e.product_id && <strong>{products.find(p => p.id === e.product_id)?.name || "Producto del catálogo"} · </strong>}{e.details}</p>{e.reference && !e.reference.startsWith("product:") && <p>Pedido / referencia: {e.reference}</p>}<small>{new Date(e.occurred_on + "T12:00:00").toLocaleDateString("es-ES")} · {e.source === "crm" ? "Registrado por el equipo" : "Declarado en conversación"}{e.amount != null ? " · " + Number(e.amount).toLocaleString("es-ES",{style:"currency",currency:e.currency}) : ""}{e.quantity ? " · " + e.quantity + " uds." : ""}</small>{e.evidence && <blockquote>{e.evidence}</blockquote>}</div>)}</div> : <p>Sin preferencias de producto, consultas ni compras registradas.</p>}
    <EntryForm contactId={contact.id} products={products} onSave={onSave} /></section>
  </article>;
}

function EntryForm({ contactId, products, onSave }: { contactId: string; products: Product[]; onSave: Save }) {
  const [kind,setKind] = useState("interest"), [product,setProduct] = useState(""), [reference,setReference] = useState(""), [details,setDetails] = useState(""), [status,setStatus] = useState("open"), [amount,setAmount] = useState(""), [quantity,setQuantity] = useState(""), [date,setDate] = useState(new Date().toLocaleDateString("en-CA")), [busy,setBusy] = useState(false);
  const save = async (event: FormEvent) => {
    event.preventDefault(); setBusy(true);
    try { if (await onSave("contact_entries",contactId,{kind,product_id:product||null,reference,details,status,amount:kind === "purchase" && amount !== "" ? Number(amount) : null,quantity:quantity ? Number(quantity) : null,occurred_on:date})) { setDetails(""); setReference(""); setAmount(""); setQuantity(""); } }
    finally { setBusy(false); }
  };
  return <details className="entry-editor"><summary>Añadir o actualizar registro</summary><p>Para actualizar un pedido o compra, usa la misma referencia. Los intereses del mismo producto se actualizan sin duplicar.</p><form onSubmit={save}>
<div className="form-row"><label>Tipo<select value={kind} onChange={e => { setKind(e.target.value); setStatus(e.target.value === "purchase" ? "declared" : "open"); }}>{Object.entries(kinds).map(([v,l]) => <option key={v} value={v}>{l}</option>)}</select></label><label>Producto<select value={product} onChange={e => setProduct(e.target.value)}><option value="">General / varios productos</option>{products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label><label>Estado<select value={status} onChange={e => setStatus(e.target.value)}>{(kind === "purchase" ? ["declared","confirmed","cancelled"] : ["open","resolved","cancelled"]).map(v => <option key={v} value={v}>{statuses[v]}</option>)}</select></label></div><div className="form-row"><label>Pedido / referencia<input maxLength={120} required={kind === "purchase"} value={reference} onChange={e => setReference(e.target.value)} /></label><label>Fecha<input type="date" required value={date} onChange={e => setDate(e.target.value)} /></label>{kind === "purchase" && <><label>Importe total (€)<input type="number" min="0" step="0.01" value={amount} onChange={e => setAmount(e.target.value)} /></label><label>Unidades<input type="number" min="1" max="10000" step="1" value={quantity} onChange={e => setQuantity(e.target.value)} /></label></>}</div><label>Detalle<textarea required maxLength={2000} value={details} onChange={e => setDetails(e.target.value)} placeholder="Qué le gusta, qué descarta, qué consulta del pedido o qué ha comprado…" /></label><button disabled={busy}>{busy ? "Guardando…" : "Guardar registro"}</button></form></details>;
}
