import { NextRequest, NextResponse } from "next/server";
import { isAdmin } from "../../../../lib/auth";
import { rpc } from "../../../../lib/supabase";
import { registrationSources } from "../../../../lib/registration-sources";
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
type Delivery={status:string;sent_at:string|null;delivered_at:string|null;read_at:string|null;error:string|null};
type Detail={contact:{id:string;[key:string]:unknown};messages:{id:string;direction:string;delivery_status:string|null;delivery?:Delivery|null}[];[key:string]:unknown};
export async function GET(request:NextRequest,context:{params:Promise<{id:string}>}) {
 if (!(await isAdmin())) return NextResponse.json({error:"No autorizado"},{status:401});
 const {id}=await context.params, before=request.nextUrl.searchParams.get("before");
 if (!uuid.test(id)||(before!==null&&!uuid.test(before))) return NextResponse.json({error:"Identificador no válido"},{status:400});
 try {
  const result=await rpc<Detail|null>("olivia_conversation_detail",{p_id:id,p_before:before});
  if(!result)return NextResponse.json({error:"Conversación no encontrada"},{status:404});
  const sources=await registrationSources([result.contact.id]);
  result.contact={...result.contact,registration_sources:sources[result.contact.id]||[]};
  const ids=result.messages.filter(m=>m.direction==="outbound").map(m=>m.id);
  const statuses=ids.length?await rpc<Record<string,Delivery|null>>("olivia_conversation_delivery_statuses",{p_conversation_id:id,p_message_ids:ids}):{};
  result.messages=result.messages.map(m=>({...m,delivery:statuses[m.id]||null}));
  return NextResponse.json(result);
 }catch{return NextResponse.json({error:"No se pudo cargar la conversación."},{status:500});}
}
