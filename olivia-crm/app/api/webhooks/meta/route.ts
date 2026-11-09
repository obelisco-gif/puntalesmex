import { createHmac, timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { POST as verifyAndStore } from "../whatsapp-status/route";
export const runtime = "nodejs";

export async function GET(request: NextRequest) {
 const token=process.env.META_WEBHOOK_VERIFY_TOKEN;
 const supplied=request.nextUrl.searchParams.get("hub.verify_token");
 const a=Buffer.from(token||""),b=Buffer.from(supplied||"");
 if(!token || !supplied || a.length!==b.length || !timingSafeEqual(a,b) || request.nextUrl.searchParams.get("hub.mode")!=="subscribe")
  return new NextResponse("No autorizado",{status:403});
 const challenge=request.nextUrl.searchParams.get("hub.challenge");
 return challenge?new NextResponse(challenge,{status:200,headers:{"Content-Type":"text/plain"}}):new NextResponse("No válido",{status:400});
}

export async function POST(request: NextRequest) {
 const verified=await verifyAndStore(request.clone());
 if(!verified.ok) return verified;
 const secret=process.env.META_APP_SECRET;
 if(!secret) return NextResponse.json({error:"No configurado"},{status:503});
 let body:unknown;
 try { body=await request.json(); } catch { return NextResponse.json({error:"Datos no válidos"},{status:400}); }
 const canonical=JSON.stringify(body);
 const signature="sha256="+createHmac("sha256",secret).update(canonical,"utf8").digest("hex");
 const target=process.env.OLIVIA_N8N_WEBHOOK_URL || "https://n8n-n8n.d1kse4.easypanel.host/webhook/sadiet";
 try {
  const result=await fetch(target,{method:"POST",headers:{"content-type":"application/json","x-hub-signature-256":signature},body:canonical,cache:"no-store",signal:AbortSignal.timeout(8000)});
  if(!result.ok) return NextResponse.json({error:"No se pudo entregar el evento"},{status:503});
  return NextResponse.json({ok:true});
 } catch { return NextResponse.json({error:"No se pudo entregar el evento"},{status:503}); }
}
