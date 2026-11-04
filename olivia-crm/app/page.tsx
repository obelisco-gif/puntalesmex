"use client";

import { FormEvent, useEffect, useState } from "react";
import { Documentation, type DocumentRecord } from "./documentation";
import { ContactCard, type Contact } from "./contact-card";
import { Conversations } from "./conversations";

type Product = { id: string; name: string; price: string | number | null; stock_status: string; image_url: string | null; internal_notes: string | null; manual_tags: string[]; permalink: string };
type Document = DocumentRecord;
type Touchpoint = { id: string; channel: string; source: string | null; campaign: string | null; medium: string | null; content: string | null; occurred_at: string; contacts: { first_name: string | null; email: string | null; phone: string | null } | null };
type Dashboard = { products: Product[]; contacts: Contact[]; documents: Document[]; touchpoints: Touchpoint[]; metrics: { products: number; contacts: number; openConversations: number; inStock: number } };

const tabs = [["resumen","Resumen"],["conversaciones","Conversaciones"],["contactos","Contactos"],["catalogo","Catálogo"],["documentacion","Documentación"],["atribucion","Atribución"]];

export default function OliviaCrm() {
  const [data, setData] = useState<Dashboard | null>(null);
  const [password, setPassword] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [tab, setTab] = useState("resumen");

  const load = async () => {
    const res = await fetch("/api/dashboard");
    if (!res.ok) { setData(null); return; }
    setData(await res.json());
  };

  useEffect(() => {
    if (new URLSearchParams(window.location.search).has("auth_error")) setNotice("El enlace no es válido o ha caducado. Solicita uno nuevo.");
    if (new URLSearchParams(window.location.search).get("tab") === "conversaciones") setTab("conversaciones");
    load().catch(() => setNotice("No se pudo conectar con el CRM. Vuelve a intentarlo."));
  }, []);

  const login = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setNotice("");
    try {
      const res = await fetch("/api/session", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email, password }) });
      const body = await res.json();
      if (!res.ok) { setNotice(body.error || "No se pudo iniciar sesión."); return; }
      setPassword(""); setNotice(""); await load();
    } catch { setNotice("No se pudo conectar. Inténtalo de nuevo."); }
    finally { setBusy(false); }
  };

  const recover = async () => {
    if (!email.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) { setNotice("Introduce tu email para recibir el enlace."); return; }
    setBusy(true); setNotice("");
    try {
      const res = await fetch("/api/auth/recover", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email }) });
      const body = await res.json();
      setNotice(res.ok ? body.message : body.error || "No se pudo solicitar el enlace.");
    } catch { setNotice("No se pudo conectar. Inténtalo de nuevo."); }
    finally { setBusy(false); }
  };

  const logout = async () => {
    setBusy(true);
    try {
      const res = await fetch("/api/session", { method: "DELETE" });
      if (res.ok) { setData(null); setPassword(""); setNotice(""); }
      else setNotice("No se pudo cerrar la sesión. Inténtalo de nuevo.");
    } catch { setNotice("No se pudo conectar. Inténtalo de nuevo.");
    } finally { setBusy(false); }
  };

  const saveResource = async (resource: string, id: string, body: Record<string, unknown>) => {
    try {
    const res = await fetch("/api/crm/" + resource + "/" + id, { method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    if (!res.ok) { const result = await res.json(); setNotice(result.error || "No se pudieron guardar los cambios."); return false; }
    setNotice("Cambios guardados."); await load(); return true;
    } catch { setNotice("No se pudo conectar. Inténtalo de nuevo."); return false; }
  };

  const saveNotes = (product: Product, notes: string, tags: string) => fetch("/api/catalog/" + product.id, {
    method: "PATCH", headers: { "content-type": "application/json" },
    body: JSON.stringify({ internal_notes: notes, manual_tags: tags.split(",").map((tag) => tag.trim()).filter(Boolean) })
  }).then((res) => { setNotice(res.ok ? "Anotaciones guardadas." : "No se pudieron guardar las anotaciones."); if (res.ok) load(); });

  const saveDocument = async (id: string | null, body: Record<string, unknown>) => {
    try {
      const res = await fetch(id ? "/api/crm/documents/" + id : "/api/documents", { method: id ? "PATCH" : "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
      const result = await res.json();
      if (!res.ok) { setNotice(result.error || "No se pudo guardar el documento."); return false; }
      setNotice("Documento guardado."); await load(); return true;
    } catch { setNotice("No se pudo conectar. Revisa el documento e inténtalo de nuevo."); return false; }
  };

  if (!data) return <main className="login-shell"><section className="login-card"><p className="eyebrow">SADIET · OLIVIA</p><h1>Acceso al CRM</h1><p>Entra con tu email y contraseña personal.</p><form onSubmit={login}><label>Email<input type="email" name="email" autoComplete="username" value={email} onChange={(event) => setEmail(event.target.value)} required autoFocus /></label><label>Contraseña<input type="password" name="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} required /></label><button disabled={busy}>{busy ? "Espera…" : "Entrar"}</button><button type="button" className="secondary" disabled={busy} onClick={recover}>Recuperar contraseña</button></form><p>Acceso reservado a las cuentas autorizadas de Sadiet.</p>{notice && <p className="notice" role="status">{notice}</p>}</section></main>;

  const titles: Record<string, string> = { resumen: "Visión general", conversaciones: "Conversaciones", contactos: "Contactos", catalogo: "Catálogo", documentacion: "Documentación", atribucion: "Atribución" };

  return <main className="app-shell">
    <aside><div className="brand"><span>●</span><strong>Olivia</strong><small>CRM Sadiet</small></div>
      {tabs.map(([id,label]) => <button key={id} className={tab === id ? "nav active" : "nav"} onClick={() => setTab(id)}>{label}</button>)}
    </aside>
    <section className="content">
      <header><div><p className="eyebrow">CENTRO COMERCIAL</p><h1>{titles[tab]}</h1></div><div className="header-actions"><button className="secondary" onClick={() => load()}>Actualizar</button><button className="secondary" disabled={busy} onClick={logout}>Cerrar sesión</button></div></header>
      {notice && <p className="notice">{notice}</p>}
      {tab === "resumen" && <Summary data={data} />}
      {tab === "catalogo" && <section className="catalog">{data.products.map((product) => <ProductCard key={product.id} product={product} onSave={saveNotes} />)}</section>}
      {tab === "contactos" && <section className="record-list">{data.contacts.length ? data.contacts.map((contact) => <ContactCard key={contact.id + contact.updated_at} contact={contact} products={data.products} onSave={saveResource} />) : <Empty title="Aún no hay contactos" text="El primer flujo de Meta creará aquí los leads con su origen y consentimiento." />}</section>}
      {tab === "conversaciones" && <Conversations products={data.products} onSave={saveResource} />}
      {tab === "documentacion" && <Documentation documents={data.documents} products={data.products} onSave={saveDocument} />}
      {tab === "atribucion" && <Attribution touchpoints={data.touchpoints} />}
    </section>
  </main>;
}

function Summary({ data }: { data: Dashboard }) {
  return <><div className="metrics"><article><span>Catálogo</span><strong>{data.metrics.products}</strong><small>productos sincronizados</small></article><article><span>Disponibles</span><strong>{data.metrics.inStock}</strong><small>con stock actual</small></article><article><span>Contactos</span><strong>{data.metrics.contacts}</strong><small>en el CRM</small></article><article><span>Conversaciones abiertas</span><strong>{data.metrics.openConversations}</strong><small>pendientes de Olivia</small></article></div><section className="panel"><h2>Preparación de Olivia</h2><p>Olivia consulta la ficha comercial y la documentación aprobada para responder. Las altas de Early Access y los permisos quedan registrados por canal; los envíos se activan cuando estén preparadas las integraciones.</p><div className="chips"><span>{data.documents.length} documentos comerciales</span><span>{data.touchpoints.length} puntos de atribución</span></div></section></>;
}

function ProductCard({ product, onSave }: { product: Product; onSave: (product: Product, notes: string, tags: string) => Promise<void> }) {
  const [notes, setNotes] = useState(product.internal_notes || "");
  const [tags, setTags] = useState(product.manual_tags?.join(", ") || "");
  return <article className="product-card"><div className="product-title">{product.image_url ? <img src={product.image_url} alt="" /> : <div className="image-placeholder" />}<div><h2>{product.name}</h2><a href={product.permalink} target="_blank">Ver en la tienda</a></div></div><div className="product-meta"><span>{product.price ? String(product.price) + " €" : "Sin precio"}</span><span className={product.stock_status === "instock" ? "stock yes" : "stock"}>{product.stock_status === "instock" ? "En stock" : "Sin stock"}</span></div><label>Anotaciones internas<textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Ej.: priorizar en campañas de otoño; revisar texto comercial…" /></label><label>Etiquetas manuales<input value={tags} onChange={(event) => setTags(event.target.value)} placeholder="ej.: top-venta, campaña-recetas" /></label><button onClick={() => onSave(product, notes, tags)}>Guardar anotaciones</button></article>;
}

function Attribution({ touchpoints }: { touchpoints: Touchpoint[] }) {
  if (!touchpoints.length) return <Empty title="Atribución de campañas" text="Cada lead de Meta guardará aquí campaña, conjunto, anuncio y su evolución comercial." />;
  return <section className="record-list">{touchpoints.map((item) => <article className="record-card" key={item.id}><div className="record-heading"><div><h2>{item.contacts?.first_name || item.contacts?.phone || "Lead sin identificar"}</h2><p>{new Date(item.occurred_at).toLocaleString("es-ES")}</p></div><span className="badge">{item.channel}</span></div><div className="attribution-grid"><span><b>Fuente</b>{item.source || "—"}</span><span><b>Campaña</b>{item.campaign || "—"}</span><span><b>Medio</b>{item.medium || "—"}</span><span><b>Contenido</b>{item.content || "—"}</span></div></article>)}</section>;
}

function Empty({ title, text }: { title: string; text: string }) { return <section className="panel empty"><h2>{title}</h2><p>{text}</p></section>; }
