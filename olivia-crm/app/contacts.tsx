"use client";
import { FormEvent, useEffect, useState } from "react";
import { ContactCard, type Contact, stages } from "./contact-card";
import { ConversationDetail } from "./conversations";
import { DeleteContact } from "./delete-contact";

type Row={id:string;first_name:string|null;email:string|null;phone:string|null;stage:string;manual_tags:string[];source:string|null;updated_at:string;score:number;conversation_id:string|null};
type Directory={rows:Row[];total:number;page:number;page_size:number};
type Props={products:{id:string;name:string}[];onSave:(resource:string,id:string,body:Record<string,unknown>)=>Promise<boolean>;earlyAccess?:boolean};
type Selected={kind:"conversation"|"contact";id:string}|null;

export function Contacts({products,onSave,earlyAccess=false}:Props){
 const [selected,setSelected]=useState<Selected>(null),[page,setPage]=useState(1),[search,setSearch]=useState(""),[q,setQ]=useState(""),[stage,setStage]=useState(""),[tag,setTag]=useState(earlyAccess?"bf2026_early_access":"");
 const [data,setData]=useState<Directory|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState(""),[revision,setRevision]=useState(0);
 useEffect(()=>{
  const sync=()=>{const p=new URLSearchParams(window.location.search);const conversation=p.get("conversation"),contact=p.get("contact");setSelected(conversation?{kind:"conversation",id:conversation}:contact?{kind:"contact",id:contact}:null);};sync();
  window.addEventListener("popstate",sync);return()=>window.removeEventListener("popstate",sync);
 },[]);
 const selectedId=selected?.id;
 useEffect(()=>{
  if(selectedId)return;
  const abort=new AbortController();setLoading(true);setError("");
  fetch("/api/contacts?"+new URLSearchParams({page:String(page),q,stage,tag}),{signal:abort.signal}).then(async r=>{const b=await r.json();if(!r.ok)throw new Error(b.error);return b;}).then(setData).catch(e=>{if(!abort.signal.aborted)setError(e.message||"No se pudo cargar el listado.");}).finally(()=>{if(!abort.signal.aborted)setLoading(false);});
  return()=>abort.abort();
 },[page,q,stage,tag,revision,selectedId]);
 const open=(item:Selected)=>{
  const u=new URL(window.location.href);u.searchParams.set("tab",earlyAccess?"acceso-prioritario":"contactos");u.searchParams.delete("conversation");u.searchParams.delete("contact");
  if(item)u.searchParams.set(item.kind,item.id);window.history.pushState({},"",u);setSelected(item);
 };
 if(selected?.kind==="conversation")return <ConversationDetail key={selected.id} id={selected.id} products={products} onSave={onSave} onBack={()=>open(null)}/>;
 if(selected?.kind==="contact")return <ContactWithoutConversation key={selected.id} id={selected.id} products={products} onSave={onSave} onBack={()=>open(null)}/>;
 const filter=(e:FormEvent)=>{e.preventDefault();setPage(1);setQ(search.trim());setRevision(v=>v+1);};
 const pages=Math.max(1,Math.ceil((data?.total||0)/50));
 return <section className="conversation-directory"><div className="directory-intro"><p>Selecciona un contacto para abrir su conversación y ficha completa.</p><button className="secondary" disabled={loading} onClick={()=>setRevision(v=>v+1)}>Actualizar contactos</button></div>
 <form className="conversation-filters" onSubmit={filter}><label>Buscar contacto<input maxLength={100} value={search} onChange={e=>setSearch(e.target.value)} placeholder="Nombre, email o teléfono"/></label><label>Fase<select value={stage} onChange={e=>{setStage(e.target.value);setPage(1);}}><option value="">Todas las fases</option>{stages.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label>{!earlyAccess&&<label>Acceso prioritario<select value={tag} onChange={e=>{setTag(e.target.value);setPage(1);}}><option value="">Todos los contactos</option><option value="bf2026_early_access">Inscritos en acceso prioritario</option></select></label>}<button>Buscar</button></form>
 {loading&&<p role="status">Cargando contactos…</p>}{error&&<p role="alert">{error}</p>}
 {!loading&&!error&&data&&<><div className="conversation-rows">{data.rows.length?data.rows.map(row=>{
  const name=row.first_name||row.phone||row.email||"Sin nombre";
  return <button className="conversation-row" key={row.id} onClick={()=>open({kind:row.conversation_id?"conversation":"contact",id:row.conversation_id||row.id})}><span className="conversation-avatar" aria-hidden="true">{name.slice(0,1).toUpperCase()}</span><span className="conversation-copy"><strong>{name}</strong><span className="conversation-preview">{[row.email,row.phone].filter(Boolean).join(" · ")}</span><span className="conversation-labels"><span>{stages.find(([v])=>v===row.stage)?.[1]||row.stage}</span>{row.manual_tags?.map(t=><span key={t}>{t==="bf2026_early_access"?"Early Access":t}</span>)}</span></span><span className="conversation-meta"><b>Score {row.score??0}/100</b><time>{new Date(row.updated_at).toLocaleDateString("es-ES")}</time><span>{row.conversation_id?"Abrir conversación y ficha →":"Abrir ficha · sin conversación →"}</span></span></button>;
 }):<p className="empty">No hay contactos con estos filtros.</p>}</div><nav className="conversation-pagination" aria-label="Páginas de contactos"><span>{data.total?`${(data.page-1)*50+1}–${Math.min(data.page*50,data.total)} de ${data.total}`:"0 resultados"} · Página {data.page} de {pages}</span><div><button className="secondary" disabled={data.page<=1} onClick={()=>setPage(data.page-1)}>← Anterior</button><button className="secondary" disabled={data.page>=pages} onClick={()=>setPage(data.page+1)}>Siguiente →</button></div></nav></>}
 </section>;
}

function ContactWithoutConversation({id,products,onSave,onBack}:Props&{id:string;onBack:()=>void}){
 const [contact,setContact]=useState<Contact|null>(null),[error,setError]=useState(""),[loading,setLoading]=useState(true),[revision,setRevision]=useState(0);
 useEffect(()=>{const abort=new AbortController();setLoading(true);setError("");fetch("/api/contacts/"+id,{signal:abort.signal}).then(async r=>{const b=await r.json();if(!r.ok)throw new Error(b.error);return b;}).then(setContact).catch(e=>{if(!abort.signal.aborted)setError(e.message);}).finally(()=>{if(!abort.signal.aborted)setLoading(false);});return()=>abort.abort();},[id,revision]);
 const save:Props["onSave"]=async(resource,target,body)=>{const ok=await onSave(resource,target,body);if(ok)setRevision(v=>v+1);return ok;};
 return <section className="conversation-workspace"><div className="conversation-back"><button className="secondary" onClick={onBack}>← Volver al listado</button><button className="secondary" disabled={loading} onClick={()=>setRevision(v=>v+1)}>Actualizar ficha</button></div>{error&&<p role="alert">{error}</p>}{loading&&<p role="status">Cargando ficha…</p>}{contact&&<><section className="conversation-control"><h3>Sin conversaciones todavía</h3><p>Este contacto tiene su ficha disponible. El historial aparecerá cuando tenga una conversación registrada.</p></section><DeleteContact contact={contact} onDeleted={onBack} disabled={loading}/><ContactCard key={contact.id+contact.updated_at} contact={contact} products={products} onSave={save}/></>}</section>;
}
