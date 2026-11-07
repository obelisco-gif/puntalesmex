"use client";
import { useId, useRef, useState } from "react";
type Contact={id:string;first_name:string|null;phone:string|null;email:string|null;updated_at:string};
export function DeleteContact({contact,onDeleted,disabled=false}:{contact:Contact;onDeleted:()=>void;disabled?:boolean}){
 const dialog=useRef<HTMLDialogElement>(null),title=useId(),description=useId();
 const [busy,setBusy]=useState(false),[error,setError]=useState("");
 const remove=async()=>{
  if(busy)return;setBusy(true);setError("");
  try{
   const response=await fetch('/api/contacts/'+contact.id,{method:'DELETE',headers:{'content-type':'application/json'},body:JSON.stringify({confirmation:'ELIMINAR',expected_updated_at:contact.updated_at})});
   const result=await response.json();if(!response.ok||!result.deleted)throw new Error(result.error||'No se pudo eliminar el perfil.');
   dialog.current?.close();onDeleted();
  }catch(e){setError(e instanceof Error?e.message:'No se pudo eliminar el perfil.');}finally{setBusy(false);}
 };
 return <><button type="button" className="delete-contact-button" disabled={disabled||busy} onClick={()=>{setError('');dialog.current?.showModal();}}>Eliminar perfil</button>
 <dialog className="delete-contact-dialog" ref={dialog} aria-labelledby={title} aria-describedby={description} onCancel={event=>{if(busy)event.preventDefault();}}>
  <h2 id={title}>¿Eliminar el perfil de Olivia?</h2><p><strong>{contact.first_name||'Contacto sin nombre'}</strong><br/>{[contact.phone,contact.email].filter(Boolean).join(' · ')}</p>
  <p id={description}>Se borrarán sus conversaciones, memoria, atributos, score, etiquetas, permisos y trabajos pendientes de Olivia. Esta acción no se puede deshacer.</p>
  <p>No elimina el perfil de Klaviyo ni los pedidos de WooCommerce. Cuando vuelva a escribir, Olivia empezará una ficha nueva.</p>
  {error&&<p role="alert">{error}</p>}<div className="delete-contact-actions"><button type="button" className="secondary" autoFocus disabled={busy} onClick={()=>dialog.current?.close()}>Cancelar</button><button type="button" className="delete-contact-confirm" disabled={busy} onClick={remove}>{busy?'Eliminando…':'Eliminar definitivamente'}</button></div>
 </dialog></>;
}
