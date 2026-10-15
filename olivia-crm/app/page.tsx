"use client";

import { FormEvent, useEffect, useState } from "react";

type Product = { id: string; name: string; price: string | number | null; stock_status: string; image_url: string | null; internal_notes: string | null; manual_tags: string[]; permalink: string };
type Contact = { id: string; first_name: string | null; email: string | null; phone: string | null; stage: string; source: string | null; manual_tags: string[]; internal_notes: string | null; preferences: Record<string, unknown>; assigned_to: string | null; updated_at: string };
type Conversation = { id: string; channel: string; status: string; priority: string; handoff_status: string; internal_notes: string | null; updated_at: string; contacts: { first_name: string | null; email: string | null; phone: string | null } | null };
type Document = { id: string; document_type: string; title: string; content: string; source_url: string | null; approval_status: string; reviewed_at: string | null; updated_at: string };
type Touchpoint = { id: string; channel: string; source: string | null; campaign: string | null; medium: string | null; content: string | null; occurred_at: string; contacts: { first_name: string | null; email: string | null; phone: string | null } | null };
type Dashboard = { products: Product[]; contacts: Contact[]; conversations: Conversation[]; documents: Document[]; touchpoints: Touchpoint[]; metrics: { products: number; contacts: number; openConversations: number; inStock: number } };

const tabs = [["resumen","Resumen"],["conversaciones","Conversaciones"],["contactos","Contactos"],["catalogo","Catálogo"],["documentacion","Documentación"],["atribucion","Atribución"]];

export default function OliviaCrm() {
  const [data, setData] = useState<Dashboard | null>(null);
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [tab, setTab] = useState("resumen");

  const load = async () => {
    const res = await fetch("/api/dashboard");
    if (!res.ok) { setData(null); return; }
    setData(await res.json());
  };

  useEffect(() => { load(); }, []);

  const login = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    const res = await fetch("/api/session", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ password }) });
    setBusy(false);
    if (!res.ok) { setNotice("La clave no es correcta."); return; }
    setPassword(""); setNotice(""); load();
  };

  const saveResource = async (resource: string, id: string, body: Record<string, unknown>) => {
    const res = await fetch("/api/crm/" + resource + "/" + id, { method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    if (!res.ok) { setNotice("No se pudieron guardar los cambios."); return; }
    setNotice("Cambios guardados."); load();
  };

  const saveNotes = (product: Product, notes: string, tags: string) => fetch("/api/catalog/" + product.id, {
    method: "PATCH", headers: { "content-type": "application/json" },
    body: JSON.stringify({ internal_notes: notes, manual_tags: tags.split(",").map((tag) => tag.trim()).filter(Boolean) })
  }).then((res) => { setNotice(res.ok ? "Anotaciones guardadas." : "No se pudieron guardar las anotaciones."); if (res.ok) load(); });

  const createDocument = async (body: Record<string, string>) => {
    const res = await fetch("/api/documents", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    if (!res.ok) { setNotice("No se pudo crear el documento."); return; }
    setNotice("Documento creado como borrador."); load();
  };

  if (!data) return <main className="login-shell"><section className="login-card"><p className="eyebrow">SADIET · OLIVIA</p><h1>CRM comercial</h1><p>Accede para gestionar conversaciones, recomendaciones y conocimiento de producto.</p><form onSubmit={login}><label>Clave de acceso<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoFocus /></label><button disabled={busy}>{busy ? "Entrando…" : "Entrar"}</button></form>{notice && <p className="notice">{notice}</p>}</section></main>;

  const titles: Record<string, string> = { resumen: "Visión general", conversaciones: "Conversaciones", contactos: "Contactos", catalogo: "Catálogo", documentacion: "Documentación", atribucion: "Atribución" };

  return <main className="app-shell">
    <aside><div className="brand"><span>●</span><strong>Olivia</strong><small>CRM Sadiet</small></div>
      {tabs.map(([id,label]) => <button key={id} className={tab === id ? "nav active" : "nav"} onClick={() => setTab(id)}>{label}</button>)}
    </aside>
    <section className="content">
      <header><div><p className="eyebrow">CENTRO COMERCIAL</p><h1>{titles[tab]}</h1></div><button className="secondary" onClick={() => load()}>Actualizar</button></header>
      {notice && <p className="notice">{notice}</p>}
      {tab === "resumen" && <Summary data={data} />}
      {tab === "catalogo" && <section className="catalog">{data.products.map((product) => <ProductCard key={product.id} product={product} onSave={saveNotes} />)}</section>}
      {tab === "contactos" && <section className="record-list">{data.contacts.length ? data.contacts.map((contact) => <ContactCard key={contact.id} contact={contact} onSave={saveResource} />) : <Empty title="Aún no hay contactos" text="El primer flujo de Meta creará aquí los leads con su origen y consentimiento." />}</section>}
      {tab === "conversaciones" && <section className="record-list">{data.conversations.length ? data.conversations.map((conversation) => <ConversationCard key={conversation.id} conversation={conversation} onSave={saveResource} />) : <Empty title="Aún no hay conversaciones" text="La cola de Olivia está lista. Las conversaciones aparecerán al recibir el primer mensaje." />}</section>}
      {tab === "documentacion" && <section className="documentation"><DocumentForm onCreate={createDocument} />{data.documents.length ? data.documents.map((document) => <DocumentCard key={document.id} document={document} onSave={saveResource} />) : <Empty title="Documentación comercial" text="Crea aquí la información que Olivia podrá consultar al recomendar un producto." />}</section>}
      {tab === "atribucion" && <Attribution touchpoints={data.touchpoints} />}
    </section>
  </main>;
}

function Summary({ data }: { data: Dashboard }) {
  return <><div className="metrics"><article><span>Catálogo</span><strong>{data.metrics.products}</strong><small>productos sincronizados</small></article><article><span>Disponibles</span><strong>{data.metrics.inStock}</strong><small>con stock actual</small></article><article><span>Contactos</span><strong>{data.metrics.contacts}</strong><small>en el CRM</small></article><article><span>Conversaciones abiertas</span><strong>{data.metrics.openConversations}</strong><small>pendientes de Olivia</small></article></div><section className="panel"><h2>Preparación de Olivia</h2><p>La cola de mensajes y el registro de decisiones están listos. El siguiente flujo registrará cada lead y entregará el recetario.</p><div className="chips"><span>{data.documents.length} documentos comerciales</span><span>{data.touchpoints.length} puntos de atribución</span></div></section></>;
}

function ProductCard({ product, onSave }: { product: Product; onSave: (product: Product, notes: string, tags: string) => Promise<void> }) {
  const [notes, setNotes] = useState(product.internal_notes || "");
  const [tags, setTags] = useState(product.manual_tags?.join(", ") || "");
  return <article className="product-card"><div className="product-title">{product.image_url ? <img src={product.image_url} alt="" /> : <div className="image-placeholder" />}<div><h2>{product.name}</h2><a href={product.permalink} target="_blank">Ver en la tienda</a></div></div><div className="product-meta"><span>{product.price ? String(product.price) + " €" : "Sin precio"}</span><span className={product.stock_status === "instock" ? "stock yes" : "stock"}>{product.stock_status === "instock" ? "En stock" : "Sin stock"}</span></div><label>Anotaciones internas<textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Ej.: priorizar en campañas de otoño; revisar texto comercial…" /></label><label>Etiquetas manuales<input value={tags} onChange={(event) => setTags(event.target.value)} placeholder="ej.: top-venta, campaña-recetas" /></label><button onClick={() => onSave(product, notes, tags)}>Guardar anotaciones</button></article>;
}

function ContactCard({ contact, onSave }: { contact: Contact; onSave: (resource: string, id: string, body: Record<string, unknown>) => Promise<void> }) {
  const [stage, setStage] = useState(contact.stage); const [notes, setNotes] = useState(contact.internal_notes || ""); const [tags, setTags] = useState(contact.manual_tags?.join(", ") || ""); const [assigned, setAssigned] = useState(contact.assigned_to || "");
  return <article className="record-card"><div className="record-heading"><div><h2>{contact.first_name || "Sin nombre"}</h2><p>{contact.email || contact.phone || "Sin datos de contacto"} · {contact.source || "Origen sin definir"}</p></div><span className="badge">{stage}</span></div><div className="form-row"><label>Etapa<select value={stage} onChange={(event) => setStage(event.target.value)}><option value="lead">Lead</option><option value="qualified">Cualificado</option><option value="customer">Cliente</option><option value="nurturing">Seguimiento</option><option value="lost">No interesado</option></select></label><label>Responsable<input value={assigned} onChange={(event) => setAssigned(event.target.value)} placeholder="Ej.: Sergio" /></label></div><label>Notas internas<textarea value={notes} onChange={(event) => setNotes(event.target.value)} /></label><label>Etiquetas<input value={tags} onChange={(event) => setTags(event.target.value)} placeholder="ej.: meta, recetas" /></label><button onClick={() => onSave("contacts", contact.id, { stage, internal_notes: notes, manual_tags: tags.split(",").map((tag) => tag.trim()).filter(Boolean), assigned_to: assigned || null })}>Guardar contacto</button></article>;
}

function ConversationCard({ conversation, onSave }: { conversation: Conversation; onSave: (resource: string, id: string, body: Record<string, unknown>) => Promise<void> }) {
  const [status, setStatus] = useState(conversation.status); const [priority, setPriority] = useState(conversation.priority); const [handoff, setHandoff] = useState(conversation.handoff_status); const [notes, setNotes] = useState(conversation.internal_notes || ""); const person = conversation.contacts?.first_name || conversation.contacts?.phone || "Contacto";
  return <article className="record-card"><div className="record-heading"><div><h2>{person}</h2><p>{conversation.channel} · Actualizada {new Date(conversation.updated_at).toLocaleString("es-ES")}</p></div><span className="badge">{status}</span></div><div className="form-row"><label>Estado<select value={status} onChange={(event) => setStatus(event.target.value)}><option value="open">Abierta</option><option value="closed">Cerrada</option><option value="paused">Pausada</option></select></label><label>Prioridad<select value={priority} onChange={(event) => setPriority(event.target.value)}><option value="normal">Normal</option><option value="high">Alta</option><option value="urgent">Urgente</option></select></label><label>Atención humana<select value={handoff} onChange={(event) => setHandoff(event.target.value)}><option value="bot">Olivia</option><option value="requested">Solicitada</option><option value="human">En manos del equipo</option></select></label></div><label>Notas internas<textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Contexto para quien retome la conversación…" /></label><button onClick={() => onSave("conversations", conversation.id, { status, priority, handoff_status: handoff, internal_notes: notes })}>Guardar seguimiento</button></article>;
}

function DocumentForm({ onCreate }: { onCreate: (body: Record<string, string>) => Promise<void> }) {
  const [title, setTitle] = useState(""); const [content, setContent] = useState(""); const [type, setType] = useState("commercial"); const [sourceUrl, setSourceUrl] = useState("");
  const submit = async (event: FormEvent) => { event.preventDefault(); await onCreate({ title, content, document_type: type, source_url: sourceUrl }); setTitle(""); setContent(""); setSourceUrl(""); };
  return <form className="record-card document-form" onSubmit={submit}><h2>Nuevo documento para Olivia</h2><p>Solo los documentos aprobados se usarán en las recomendaciones.</p><div className="form-row"><label>Título<input required value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Guía de recomendación de Café Verde" /></label><label>Tipo<select value={type} onChange={(event) => setType(event.target.value)}><option value="commercial">Comercial</option><option value="product">Producto</option><option value="faq">Preguntas frecuentes</option><option value="safety">Uso y precauciones</option></select></label></div><label>Contenido<textarea required value={content} onChange={(event) => setContent(event.target.value)} placeholder="Información validada que Olivia puede utilizar…" /></label><label>Fuente opcional<input value={sourceUrl} onChange={(event) => setSourceUrl(event.target.value)} placeholder="https://…" /></label><button>Crear borrador</button></form>;
}

function DocumentCard({ document, onSave }: { document: Document; onSave: (resource: string, id: string, body: Record<string, unknown>) => Promise<void> }) {
  const [title, setTitle] = useState(document.title); const [content, setContent] = useState(document.content); const [status, setStatus] = useState(document.approval_status); const [url, setUrl] = useState(document.source_url || "");
  return <article className="record-card"><div className="record-heading"><div><h2>{document.document_type}</h2><p>Actualizado {new Date(document.updated_at).toLocaleDateString("es-ES")}</p></div><span className="badge">{status}</span></div><label>Título<input value={title} onChange={(event) => setTitle(event.target.value)} /></label><label>Contenido<textarea value={content} onChange={(event) => setContent(event.target.value)} /></label><div className="form-row"><label>Estado<select value={status} onChange={(event) => setStatus(event.target.value)}><option value="draft">Borrador</option><option value="approved">Aprobado para Olivia</option><option value="archived">Archivado</option></select></label><label>Fuente<input value={url} onChange={(event) => setUrl(event.target.value)} /></label></div><button onClick={() => onSave("documents", document.id, { title, content, source_url: url || null, approval_status: status })}>Guardar documento</button></article>;
}

function Attribution({ touchpoints }: { touchpoints: Touchpoint[] }) {
  if (!touchpoints.length) return <Empty title="Atribución de campañas" text="Cada lead de Meta guardará aquí campaña, conjunto, anuncio y su evolución comercial." />;
  return <section className="record-list">{touchpoints.map((item) => <article className="record-card" key={item.id}><div className="record-heading"><div><h2>{item.contacts?.first_name || item.contacts?.phone || "Lead sin identificar"}</h2><p>{new Date(item.occurred_at).toLocaleString("es-ES")}</p></div><span className="badge">{item.channel}</span></div><div className="attribution-grid"><span><b>Fuente</b>{item.source || "—"}</span><span><b>Campaña</b>{item.campaign || "—"}</span><span><b>Medio</b>{item.medium || "—"}</span><span><b>Contenido</b>{item.content || "—"}</span></div></article>)}</section>;
}

function Empty({ title, text }: { title: string; text: string }) { return <section className="panel empty"><h2>{title}</h2><p>{text}</p></section>; }
