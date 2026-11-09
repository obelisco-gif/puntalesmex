import { NextResponse } from "next/server";
import { rpc } from "../../../../lib/supabase";
const { verifyMetaSignature } = require("../../../../lib/verify-meta-signature.cjs");

export const runtime = "nodejs";
const allowed = new Set(["sent","delivered","read","failed"]);
const maxBytes = 1024 * 1024;
type MetaStatus = { id?: unknown; status?: unknown; timestamp?: unknown; errors?: unknown };
type MetaChange = { field?: unknown; value?: { metadata?: { phone_number_id?: unknown }; statuses?: MetaStatus[] } };
type MetaEntry = { id?: unknown; changes?: MetaChange[] };

export async function POST(request: Request) {
 const secret = process.env.META_APP_SECRET;
 if (!secret) return NextResponse.json({error:"No configurado"}, {status:503});
 if (Number(request.headers.get("content-length") || 0) > maxBytes) return NextResponse.json({error:"Demasiado grande"}, {status:413});
 const raw = Buffer.from(await request.arrayBuffer());
 if (raw.length > maxBytes) return NextResponse.json({error:"Demasiado grande"}, {status:413});
 if (!verifyMetaSignature(raw, request.headers.get("x-hub-signature-256"), secret))
  return NextResponse.json({error:"No autorizado"}, {status:401});
 let body: {object?:unknown;entry?:MetaEntry[]};
 try { body=JSON.parse(raw.toString("utf8")); }
 catch { return NextResponse.json({error:"Datos no válidos"}, {status:400}); }
 if (body.object!=="whatsapp_business_account" || !Array.isArray(body.entry))
  return NextResponse.json({error:"Datos no válidos"}, {status:400});
 const events: Record<string,unknown>[]=[];
 for (const entry of body.entry) for (const change of Array.isArray(entry.changes)?entry.changes:[]) {
  if(change.field!=="messages") continue;
  const waba=entry.id, phone=change.value?.metadata?.phone_number_id;
  if(typeof waba!=="string" || typeof phone!=="string") return NextResponse.json({error:"Cuenta no válida"}, {status:400});
  try {
   if(!(await rpc<boolean>("olivia_whatsapp_source_allowed",{p_waba_id:waba,p_phone_number_id:phone})))
    return NextResponse.json({error:"Cuenta no autorizada"}, {status:403});
  } catch { return NextResponse.json({error:"No se pudo verificar la cuenta"}, {status:503}); }
  for(const item of Array.isArray(change.value?.statuses)?change.value.statuses:[]) {
   if(typeof item.id!=="string" || typeof item.status!=="string" || !allowed.has(item.status)) continue;
   if(typeof item.timestamp!=="string" || !/^\d{1,12}$/.test(item.timestamp)) return NextResponse.json({error:"Fecha no válida"}, {status:400});
   const time=new Date(Number(item.timestamp)*1000);
   if(Number.isNaN(time.getTime())) return NextResponse.json({error:"Fecha no válida"}, {status:400});
   const error=Array.isArray(item.errors)&&item.errors[0]&&typeof item.errors[0]==="object"?item.errors[0] as Record<string,unknown>:{};
   const detail=error.error_data && typeof error.error_data==="object"?(error.error_data as Record<string,unknown>).details:null;
   const title=[error.title,error.message,detail].filter((x):x is string=>typeof x==="string"&&x.length>0).filter((x,i,a)=>a.indexOf(x)===i).join(" · ").slice(0,300);
   events.push({p_waba_id:waba,p_phone_number_id:phone,p_message_id:item.id,p_status:item.status,p_occurred_at:time.toISOString(),p_error_code:error.code==null?null:String(error.code).slice(0,40),p_error_title:title||null});
   if(events.length>100) return NextResponse.json({error:"Demasiados eventos"}, {status:413});
  }
 }
 if (new URL(request.url).searchParams.get("verify_only")==="1") return NextResponse.json({ok:true});
 try {
  for (const event of events) await rpc("olivia_record_whatsapp_status",event);
  return NextResponse.json({ok:true});
 } catch { return NextResponse.json({error:"No se pudieron guardar los estados"}, {status:503}); }
}
