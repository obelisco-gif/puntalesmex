"use client";
import { FormEvent, useEffect, useRef, useState } from "react";
import { ContactCard, type Contact } from "./contact-card";
import { DeleteContact } from "./delete-contact";

type Conversation={id:string;contact_id:string;channel:string;status:string;priority:string;handoff_status:string;internal_notes:string|null;updated_at:string};
type Row=Conversation&{contact:{first_name:string|null;email:string|null;phone:string|null;stage:string;tags:string[]};preview:string;score:number};
type Directory={rows:Row[];total:number;page:number;page_size:number};
type Message={id:string;direction:string;body:string|null;created_at:string;delivery_status:string|null;sender_role?:string|null};
type Detail={conversation:Conversation;contact:Contact;messages:Message[];has_older:boolean;message_count:number;outbound_enabled:boolean;channel_consents:{channel:string;status:string}[]};
type Props={products:{id:string;name:string}[];onSave:(resource:string,id:string,body:Record<string,unknown>)=>Promise<boolean>};
const controls:Record<string,string>={bot:"Olivia",human:"Equipo Sadiet",pending_human:"Pendiente del equipo",resolved:"Resuelta"};
const statuses:Record<string,string>={open:"Abierta",paused:"Pausada",closed:"Cerrada"};
const deliveries:Record<string,string>={pending:"En cola",processing:"En proceso de envío",sent:"Enviado",delivered:"Entregado",failed:"Envío fallido",cancelled:"Envío cancelado"};
const date=(value:string)=>new Date(value).toLocaleString("es-ES",{dateStyle:"short",timeStyle:"short",timeZone:"Europe/Madrid"});

export function Conversations({products,onSave}:Props){
 const [selected,setSelected]=useState<string|null>(null),[page,setPage]=useState(1),[search,setSearch]=useState(""),[q,setQ]=useState(""),[status,setStatus]=useState(""),[control,setControl]=useState("");
 const [directory,setDirectory]=useState<Directory|null>(null),[error,setError]=useState(""),[loading,setLoading]=useState(false),[revision,setRevision]=useState(0);
 useEffect(()=>{
  const sync=()=>setSelected(new URLSearchParams(window.location.search).get("conversation"));sync();
  window.addEventListener("popstate",sync);return()=>window.removeEventListener("popstate",sync);
 },[]);
 useEffect(()=>{
  if(selected)return;
  const abort=new AbortController();setLoading(true);setError("");
  const params=new URLSearchParams({page:String(page),q,status,control});
  fetch("/api/conversations?"+params,{signal:abort.signal}).then(async r=>{const b=await r.json();if(!r.ok)throw new Error(b.error);return b;}).then(setDirectory).catch(e=>{if(!abort.signal.aborted)setError(e.message||"No se pudo cargar el listado.");}).finally(()=>{if(!abort.signal.aborted)setLoading(false);});
  return()=>abort.abort();
 },[page,q,status,control,revision,selected]);
 const open=(id:string|null)=>{const u=new URL(window.location.href);u.searchParams.set("tab","conversaciones");if(id)u.searchParams.set("conversation",id);else u.searchParams.delete("conversation");window.history.pushState({},"",u);setSelected(id);};
 if(selected)return <ConversationDetail key={selected} id={selected} products={products} onSave={onSave} onBack={()=>open(null)}/>;
 const filter=(event:FormEvent)=>{event.preventDefault();setPage(1);setQ(search.trim());setRevision(v=>v+1);};
 const pages=Math.max(1,Math.ceil((directory?.total||0)/50));
 return <section className="conversation-directory">
  <div className="directory-intro"><p>Abre un chat para ver su historial y la ficha completa del contacto.</p><button className="secondary" disabled={loading} onClick={()=>setRevision(v=>v+1)}>Actualizar listado</button></div>
  <form className="conversation-filters" onSubmit={filter}><label>Buscar contacto<input maxLength={100} value={search} onChange={e=>setSearch(e.target.value)} placeholder="Nombre, email o teléfono"/></label><label>Estado<select value={status} onChange={e=>{setStatus(e.target.value);setPage(1);}}><option value="">Todos los estados</option>{Object.entries(statuses).map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label><label>Control<select value={control} onChange={e=>{setControl(e.target.value);setPage(1);}}><option value="">Todo el equipo</option>{Object.entries(controls).map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label><button>Buscar</button></form>
  {error&&<p role="alert">{error}</p>}{loading&&<p role="status">Cargando conversaciones…</p>}
  {!loading&&!error&&directory&&<><div className="conversation-rows">{directory.rows.length?directory.rows.map(row=>{
   const name=row.contact.first_name||row.contact.phone||row.contact.email||"Sin nombre";
   return <button className="conversation-row" key={row.id} onClick={()=>open(row.id)}><span className="conversation-avatar" aria-hidden="true">{name.slice(0,1).toUpperCase()}</span><span className="conversation-copy"><strong>{name}</strong><span className="conversation-preview">{row.preview}</span><span className="conversation-labels"><span>{row.channel} · {statuses[row.status]}</span><span className={row.handoff_status==="human"?"human-chip":""}>Control: {controls[row.handoff_status]||row.handoff_status}</span>{row.contact.tags?.includes("bf2026_early_access")&&<span>Early Access</span>}</span></span><span className="conversation-meta"><b>Score {row.score??0}/100</b><time>{date(row.updated_at)}</time><span>Abrir conversación →</span></span></button>;
  }):<p className="empty">No hay conversaciones con estos filtros.</p>}</div><nav className="conversation-pagination" aria-label="Páginas de conversaciones"><span>{directory.total?`${(directory.page-1)*50+1}–${Math.min(directory.page*50,directory.total)} de ${directory.total}`:"0 resultados"} · Página {directory.page} de {pages}</span><div><button className="secondary" disabled={directory.page<=1} onClick={()=>setPage(directory.page-1)}>← Anterior</button><button className="secondary" disabled={directory.page>=pages} onClick={()=>setPage(directory.page+1)}>Siguiente →</button></div></nav></>}
 </section>;
}

export function ConversationDetail({id,products,onSave,onBack}:Props&{id:string;onBack:()=>void}){
 const [detail,setDetail]=useState<Detail|null>(null),[error,setError]=useState(""),[notice,setNotice]=useState(""),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[older,setOlder]=useState(false),[revision,setRevision]=useState(0);
 const [reply,setReply]=useState("");
 const replyRequest=useRef<{body:string;id:string}|null>(null);
 useEffect(()=>{
  const abort=new AbortController();setLoading(true);setError("");
  fetch("/api/conversations/"+id,{signal:abort.signal}).then(async r=>{const b=await r.json();if(!r.ok)throw new Error(b.error);return b;}).then(setDetail).catch(e=>{if(!abort.signal.aborted)setError(e.message||"No se pudo cargar el chat.");}).finally(()=>{if(!abort.signal.aborted)setLoading(false);});
  return()=>abort.abort();
 },[id,revision]);
 const refresh=()=>setRevision(v=>v+1);
 const sendReply=async(e:FormEvent)=>{
  e.preventDefault();if(!detail||busy||loading||!reply.trim())return;
  const text=reply.trim();
  if(!replyRequest.current||replyRequest.current.body!==text)replyRequest.current={body:text,id:crypto.randomUUID()};
  setBusy(true);setNotice("");setError("");
  try{
   const r=await fetch("/api/conversations/"+id+"/reply",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({body:text,request_id:replyRequest.current.id,expected_updated_at:detail.conversation.updated_at})});
   const b=await r.json();if(!r.ok)throw new Error(b.error||"No se pudo añadir el mensaje a la cola.");
   setReply("");replyRequest.current=null;
   setNotice((b.duplicate?"Este mensaje ya estaba registrado.":"Mensaje añadido a la cola. El equipo tiene el control.")+(!b.outbound_enabled?" Los envíos de WhatsApp están pausados; todavía no se ha enviado.":"")+(b.in_flight?" Había otro envío en proceso; podría completarse.":""));refresh();
  }catch(e){setError(e instanceof Error?e.message:"No se pudo confirmar el envío. Reintenta con el mismo texto para evitar duplicados.");}finally{setBusy(false);}
 };
 const save=async(resource:string,target:string,body:Record<string,unknown>)=>{const ok=await onSave(resource,target,body);if(ok)refresh();return ok;};
 const takeControl=async(target:string)=>{
  if(!detail)return;setBusy(true);setNotice("");setError("");
  try{
   const r=await fetch("/api/crm/conversations/"+id,{method:"PATCH",headers:{"content-type":"application/json"},body:JSON.stringify({handoff_status:target,expected_updated_at:detail.conversation.updated_at})});const b=await r.json();
   if(!r.ok)throw new Error(b.error||"No se pudo cambiar el control.");
   setNotice((target==="human"?"El equipo tiene el control. Olivia queda pausada en este chat.":"Control devuelto a Olivia para los mensajes nuevos.")+(b.in_flight?" Hay un envío que ya estaba en proceso; podría completarse.":""));refresh();
  }catch(e){setError(e instanceof Error?e.message:"No se pudo cambiar el control.");}finally{setBusy(false);}
 };
 const loadOlder=async()=>{
  if(!detail?.messages.length)return;setOlder(true);setError("");
  try{const r=await fetch("/api/conversations/"+id+"?before="+detail.messages[0].id);const b=await r.json();if(!r.ok)throw new Error(b.error);setDetail(current=>current?{...current,messages:[...b.messages,...current.messages],has_older:b.has_older}:current);}
  catch(e){setError(e instanceof Error?e.message:"No se pudieron cargar los mensajes anteriores.");}finally{setOlder(false);}
 };
 return <section className="conversation-workspace"><div className="conversation-back"><button className="secondary" onClick={onBack}>← Volver al listado</button><button className="secondary" disabled={loading||busy||older} onClick={refresh}>Actualizar conversación</button></div>{error&&<p role="alert">{error}</p>}{notice&&<p className="notice" role="status">{notice}</p>}{loading&&<p role="status">Cargando conversación…</p>}
 {detail&&<><div className="conversation-identity"><div><p className="eyebrow">{detail.conversation.channel.toUpperCase()} · {statuses[detail.conversation.status]}</p><h2>{detail.contact.first_name||detail.contact.phone||detail.contact.email||"Sin nombre"}</h2><p>{detail.contact.phone||"Sin WhatsApp"} · {detail.contact.email||"Sin email"}</p></div><div className="conversation-identity-actions"><span className="badge">Score {detail.contact.score?.value??0}/100</span><DeleteContact contact={detail.contact} onDeleted={onBack} disabled={busy||loading}/></div></div><div className="conversation-columns"><div className="conversation-main"><section className={"conversation-control "+(detail.conversation.handoff_status==="human"?"human":"")}><p className="eyebrow">CONTROL DE LA CONVERSACIÓN</p><h3>{detail.conversation.handoff_status==="human"?"El equipo tiene el control":detail.conversation.handoff_status==="bot"?"Olivia tiene el control":controls[detail.conversation.handoff_status]}</h3><p>{detail.conversation.handoff_status==="bot"?"Puedes tomar el control para pausar a Olivia en este chat.":"Puedes devolverlo a Olivia para que atienda los mensajes nuevos."}</p><div className="control-actions">{detail.conversation.handoff_status!=="human"&&<button disabled={busy||loading} onClick={()=>takeControl("human")}>Tomar el control</button>}{detail.conversation.handoff_status!=="bot"&&<button disabled={busy||loading} onClick={()=>takeControl("bot")}>Devolver el control a Olivia</button>}</div><small>El cambio no envía mensajes ni modifica los permisos comerciales.</small></section>
 <section className="conversation-history"><div className="record-heading"><h3>Historial de conversación</h3><span>{detail.message_count} mensajes</span></div>{detail.has_older&&<button className="secondary" disabled={older||loading} onClick={loadOlder}>{older?"Cargando…":"Cargar mensajes anteriores"}</button>}<div className="message-thread" aria-label="Historial de mensajes">{detail.messages.length?detail.messages.map(m=><div key={m.id} className={"message "+(m.direction==="outbound"?"outbound":"inbound")}><span>{m.direction==="outbound"?(m.sender_role==="human"?"Equipo Sadiet":"Sadiet · salida"):detail.contact.first_name||"Contacto"}</span><p>{m.body||"Contenido multimedia o sin texto"}</p><time>{date(m.created_at)}</time>{m.direction==="outbound"&&<small className="delivery-status">{m.delivery_status?deliveries[m.delivery_status]||m.delivery_status:"Estado de envío no disponible"}</small>}</div>):<p>Todavía no hay mensajes guardados.</p>}</div></section>
 {detail.conversation.channel==="whatsapp"&&<form className="record-card manual-composer" onSubmit={sendReply}><p className="eyebrow">RESPUESTA DEL EQUIPO</p><h3>Escribir al contacto</h3><label>Mensaje de WhatsApp<textarea required maxLength={2000} value={reply} disabled={busy} onChange={e=>setReply(e.target.value)} placeholder="Escribe tu respuesta…"/></label><small>{reply.length}/2000 · El mensaje se registrará en el historial y se añadirá a la cola de envío.</small>{!detail.outbound_enabled&&<p className="queue-paused" role="status">Los envíos de WhatsApp están pausados. El mensaje quedará en cola hasta activar la salida.</p>}<button disabled={busy||loading||!detail.contact.phone||!reply.trim()}>{busy?"Guardando…":detail.conversation.handoff_status==="human"?"Enviar como equipo":"Enviar como equipo y tomar el control"}</button></form>}
 <ConversationFollowup key={detail.conversation.id+detail.conversation.updated_at} conversation={detail.conversation} onSave={save}/></div>
 <div className="conversation-contact"><ContactCard compact key={detail.contact.id+detail.contact.updated_at} contact={detail.contact} products={products} onSave={save}/><section className="record-card"><h3>Permisos por canal</h3>{detail.channel_consents.length?detail.channel_consents.map(c=><p key={c.channel}>{c.channel}: {c.status==="granted"?"Autorizado":c.status==="revoked"?"Baja":c.status}</p>):<p>Sin permisos registrados.</p>}</section></div></div></>}
 </section>;
}

function ConversationFollowup({conversation,onSave}:{conversation:Conversation;onSave:Props["onSave"]}){
 const [status,setStatus]=useState(conversation.status),[priority,setPriority]=useState(conversation.priority),[notes,setNotes]=useState(conversation.internal_notes||""),[busy,setBusy]=useState(false);
 const submit=async(e:FormEvent)=>{e.preventDefault();setBusy(true);try{await onSave("conversations",conversation.id,{status,priority,internal_notes:notes,expected_updated_at:conversation.updated_at});}finally{setBusy(false);}};
 return <form className="record-card" onSubmit={submit}><h3>Seguimiento interno</h3><div className="form-row"><label>Estado<select value={status} onChange={e=>setStatus(e.target.value)}>{Object.entries(statuses).map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label><label>Prioridad<select value={priority} onChange={e=>setPriority(e.target.value)}>{[["low","Baja"],["normal","Normal"],["high","Alta"],["urgent","Urgente"]].map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label></div><label>Notas del chat<textarea maxLength={10000} value={notes} onChange={e=>setNotes(e.target.value)}/></label><button disabled={busy}>{busy?"Guardando…":"Guardar seguimiento"}</button></form>;
}
