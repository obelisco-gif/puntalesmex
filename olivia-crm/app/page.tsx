"use client";

import { FormEvent, useEffect, useState } from "react";

type Product = { id: string; name: string; price: string | null; stock_status: string; image_url: string | null; internal_notes: string | null; manual_tags: string[]; permalink: string };
type Dashboard = { products: Product[]; metrics: { products: number; contacts: number; openConversations: number; inStock: number }; documents: number; touchpoints: number };

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

  const saveNotes = async (product: Product, notes: string, tags: string) => {
    const res = await fetch("/api/catalog/" + product.id, {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ internal_notes: notes, manual_tags: tags.split(",").map((tag) => tag.trim()).filter(Boolean) })
    });
    if (!res.ok) { setNotice("No se pudieron guardar las anotaciones."); return; }
    setNotice("Anotaciones guardadas.");
    load();
  };

  if (!data) return <main className="login-shell"><section className="login-card"><p className="eyebrow">SADIET · OLIVIA</p><h1>CRM comercial</h1><p>Accede para gestionar conversaciones, recomendaciones y conocimiento de producto.</p><form onSubmit={login}><label>Clave de acceso<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoFocus /></label><button disabled={busy}>{busy ? "Entrando…" : "Entrar"}</button></form>{notice && <p className="notice">{notice}</p>}</section></main>;

  return <main className="app-shell">
    <aside><div className="brand"><span>●</span><strong>Olivia</strong><small>CRM Sadiet</small></div>
      {[["resumen","Resumen"],["conversaciones","Conversaciones"],["contactos","Contactos"],["catalogo","Catálogo"],["documentacion","Documentación"],["atribucion","Atribución"]].map(([id,label]) => <button key={id} className={tab === id ? "nav active" : "nav"} onClick={() => setTab(id)}>{label}</button>)}
    </aside>
    <section className="content">
      <header><div><p className="eyebrow">CENTRO COMERCIAL</p><h1>{tab === "resumen" ? "Visión general" : tab[0].toUpperCase() + tab.slice(1)}</h1></div><button className="secondary" onClick={() => load()}>Actualizar</button></header>
      {notice && <p className="notice">{notice}</p>}
      {tab === "resumen" && <><div className="metrics">
        <article><span>Catálogo</span><strong>{data.metrics.products}</strong><small>productos sincronizados</small></article>
        <article><span>Disponibles</span><strong>{data.metrics.inStock}</strong><small>con stock actual</small></article>
        <article><span>Contactos</span><strong>{data.metrics.contacts}</strong><small>en el CRM</small></article>
        <article><span>Conversaciones abiertas</span><strong>{data.metrics.openConversations}</strong><small>pendientes de Olivia</small></article>
      </div><section className="panel"><h2>Preparación de Olivia</h2><p>El catálogo está conectado. El siguiente paso es aprobar documentación comercial y definir los flujos de cualificación.</p><div className="chips"><span>{data.documents} documentos de producto</span><span>{data.touchpoints} puntos de atribución</span></div></section></>}
      {tab === "catalogo" && <section className="catalog">{data.products.map((product) => <ProductCard key={product.id} product={product} onSave={saveNotes} />)}</section>}
      {["conversaciones","contactos","documentacion","atribucion"].includes(tab) && <section className="panel empty"><h2>{tab === "conversaciones" ? "Aún no hay conversaciones" : tab === "contactos" ? "Aún no hay contactos" : tab === "documentacion" ? "Documentación de productos" : "Atribución de campañas"}</h2><p>Esta sección quedará alimentada cuando conectemos el primer flujo de Meta y WhatsApp con Olivia.</p></section>}
    </section>
  </main>;
}

function ProductCard({ product, onSave }: { product: Product; onSave: (product: Product, notes: string, tags: string) => void }) {
  const [notes, setNotes] = useState(product.internal_notes || "");
  const [tags, setTags] = useState(product.manual_tags?.join(", ") || "");
  return <article className="product-card">
    <div className="product-title">{product.image_url ? <img src={product.image_url} alt="" /> : <div className="image-placeholder" />}<div><h2>{product.name}</h2><a href={product.permalink} target="_blank">Ver en la tienda</a></div></div>
    <div className="product-meta"><span>{product.price ? product.price + " €" : "Sin precio"}</span><span className={product.stock_status === "instock" ? "stock yes" : "stock"}>{product.stock_status === "instock" ? "En stock" : "Sin stock"}</span></div>
    <label>Anotaciones internas<textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Ej.: priorizar en campañas de otoño; revisar texto comercial…" /></label>
    <label>Etiquetas manuales<input value={tags} onChange={(event) => setTags(event.target.value)} placeholder="ej.: top-venta, campaña-recetas" /></label>
    <button onClick={() => onSave(product, notes, tags)}>Guardar anotaciones</button>
  </article>;
}