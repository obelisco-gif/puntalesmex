"use client";

import { FormEvent, useId, useState } from "react";

export type DocumentRecord = { id: string; title: string; content: string; source_url: string | null; approval_status: string; updated_at: string; routing_packages: string[]; catalog_product_ids: string[] };
type ProductOption = { id: string; name: string };
const topics: Record<string,string> = {
  commercial:"Comercial", products:"Productos", usage:"Modo de empleo", ingredients:"Ingredientes y alérgenos",
  storage:"Conservación", safety:"Precauciones", comparison:"Comparativas", faq:"Preguntas frecuentes",
  black_friday:"Black Friday", early_access:"Acceso anticipado", orders:"Pedidos", payments:"Pagos",
  shipping:"Envíos", returns:"Devoluciones", club:"Club Sadiet", support:"Atención al cliente",
  reference:"Fuentes y recursos", always:"Base permanente", opt_out:"Bajas y STOP", internal_ops:"Uso interno"
};
const statusLabels: Record<string,string> = { draft:"Borrador", approved:"Aprobado para Olivia", archived:"Archivado" };
const label = (topic: string) => topics[topic] || topic.replaceAll("_"," ");
const slug = (name: string) => name.trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g,"").replace(/[^a-z0-9]+/g,"_").replace(/^_+|_+$/g,"").slice(0,64);

export function Documentation({ documents, products, onSave }: {
  documents: DocumentRecord[]; products: ProductOption[];
  onSave: (id: string | null, body: Record<string,unknown>) => Promise<boolean>;
}) {
  const available = [...new Set([...Object.keys(topics), ...documents.flatMap(d => d.routing_packages || [])])];
  return <section className="documentation">
    <section className="panel doc-intro"><h2>Documentación para Olivia</h2><p>Relaciona cada documento con los productos que corresponda y combina sus temas. Un documento puede ser comercial, tratar Black Friday y estar vinculado a varios productos.</p></section>
    <DocumentEditor products={products} availableTopics={available} onSave={onSave} />
    {documents.map(document => <DocumentEditor key={document.id + document.updated_at} document={document} products={products} availableTopics={available} onSave={onSave} />)}
  </section>;
}

function DocumentEditor({ document, products, availableTopics, onSave }: {
  document?: DocumentRecord; products: ProductOption[]; availableTopics: string[];
  onSave: (id: string | null, body: Record<string,unknown>) => Promise<boolean>;
}) {
  const id = useId();
  const [title,setTitle] = useState(document?.title || "");
  const [content,setContent] = useState(document?.content || "");
  const [source,setSource] = useState(document?.source_url || "");
  const [status,setStatus] = useState(document?.approval_status || "draft");
  const [selectedTopics,setSelectedTopics] = useState<string[]>(document?.routing_packages || ["commercial"]);
  const [selectedProducts,setSelectedProducts] = useState<string[]>(document?.catalog_product_ids || []);
  const [newTopic,setNewTopic] = useState("");
  const [extraTopics,setExtraTopics] = useState<string[]>([]);
  const [search,setSearch] = useState("");
  const [busy,setBusy] = useState(false);
  const [error,setError] = useState("");
  const allTopics = [...new Set([...availableTopics,...selectedTopics,...extraTopics])];
  const toggle = (values: string[], value: string) => values.includes(value) ? values.filter(v => v!==value) : [...values,value];
  const addTopic = () => {
    const value = slug(newTopic);
    if (!value) { setError("Escribe un nombre para el tema."); return; }
    setExtraTopics(values => [...new Set([...values,value])]);
    setSelectedTopics(values => [...new Set([...values,value])]);
    setNewTopic(""); setError("");
  };
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!selectedTopics.length) { setError("Selecciona al menos un tema."); return; }
    if (selectedTopics.includes("always") && selectedProducts.length) { setError("La Base permanente debe ser general. Quita los productos relacionados para usarla en todos los turnos."); return; }
    setBusy(true); setError("");
    try {
      const ok = await onSave(document?.id || null, { title,content,source_url:source,approval_status:status,routing_packages:selectedTopics,catalog_product_ids:selectedProducts });
      if (ok && !document) { setTitle(""); setContent(""); setSource(""); setStatus("draft"); setSelectedTopics(["commercial"]); setSelectedProducts([]); setSearch(""); }
      if (!ok) setError("No se ha guardado. Conservamos tus cambios para que puedas revisarlos.");
    } catch { setError("No se pudo conectar. Tus cambios siguen aquí."); }
    finally { setBusy(false); }
  };
  return <form className="record-card doc-editor" onSubmit={submit}>
    <div className="record-heading"><div><h2>{document ? document.title : "Nuevo documento"}</h2>{document && <p>Actualizado {new Date(document.updated_at).toLocaleDateString("es-ES")}</p>}</div><span className="badge">{statusLabels[status]}</span></div>
    <label htmlFor={id+"title"}>Título<input id={id+"title"} required maxLength={240} value={title} onChange={e=>setTitle(e.target.value)} /></label>
    <label htmlFor={id+"content"}>Contenido<textarea id={id+"content"} required maxLength={100000} className="doc-content" value={content} onChange={e=>setContent(e.target.value)} /></label>
    <fieldset className="doc-fieldset"><legend>Productos relacionados</legend><p>Selecciona todos los productos a los que se aplica. Déjalo vacío si la información es general.</p>
      <label htmlFor={id+"search"}>Buscar producto<input id={id+"search"} type="search" value={search} onChange={e=>setSearch(e.target.value)} placeholder="Nombre del producto" /></label>
      <div className="doc-selected" aria-live="polite">{selectedProducts.length ? selectedProducts.length+" productos relacionados" : "Información general"}</div>
      <div className="doc-product-options">{products.filter(p=>p.name.toLocaleLowerCase().includes(search.toLocaleLowerCase())).map(product=><label className="doc-option" key={product.id}><input type="checkbox" checked={selectedProducts.includes(product.id)} onChange={()=>setSelectedProducts(values=>toggle(values,product.id))} /><span>{product.name}</span></label>)}</div>
    </fieldset>
    <fieldset className="doc-fieldset"><legend>Temas</legend><p>Puedes combinar varios temas y añadir otros cuando los necesites.</p>
      <div className="doc-topic-options">{allTopics.map(topic=><label className="doc-option" key={topic}><input type="checkbox" checked={selectedTopics.includes(topic)} onChange={()=>setSelectedTopics(values=>toggle(values,topic))} /><span>{label(topic)}</span></label>)}</div>
      <div className="doc-topic-create"><label htmlFor={id+"topic"}>Nuevo tema<input id={id+"topic"} value={newTopic} maxLength={64} onChange={e=>setNewTopic(e.target.value)} onKeyDown={e=>{if(e.key==="Enter"){e.preventDefault();addTopic();}}} placeholder="Ej.: conservación" /></label><button className="secondary" type="button" onClick={addTopic}>Añadir tema</button></div>
      {selectedTopics.includes("internal_ops") && <p>Los documentos de uso interno no se incluyen en las respuestas de Olivia.</p>}
      {selectedTopics.includes("always") && <p>Base permanente: cuando esté aprobado, ambos agentes cargarán este documento en cada turno. Úsalo para tono, idioma, saludos, políticas y orientación comercial. Mantén aquí un resumen breve de la promoción; los detalles pueden ir en otros documentos.</p>}
    </fieldset>
    <div className="form-row"><label htmlFor={id+"state"}>Estado<select id={id+"state"} value={status} onChange={e=>setStatus(e.target.value)}>{Object.entries(statusLabels).map(([value,name])=><option key={value} value={value}>{name}</option>)}</select></label><label htmlFor={id+"source"}>Fuente opcional<input id={id+"source"} type="url" value={source} onChange={e=>setSource(e.target.value)} placeholder="https://…" /></label></div>
    <button disabled={busy}>{busy ? "Guardando…" : document ? "Guardar documento" : "Crear documento"}</button>
    {error && <p className="notice" role="alert">{error}</p>}
  </form>;
}
