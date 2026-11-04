import { NextRequest, NextResponse } from "next/server";
import { adminUser, sameOrigin } from "../../../../../lib/auth";
import { rpc } from "../../../../../lib/supabase";
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function POST(request:NextRequest,context:{params:Promise<{id:string}>}){
 if(!sameOrigin(request))return NextResponse.json({error:"Origen no permitido"},{status:403});
 const user=await adminUser();if(!user)return NextResponse.json({error:"No autorizado"},{status:401});
 const {id}=await context.params;
 try{
  const b=await request.json();
  if(!uuid.test(id)||typeof b.body!=="string"||!b.body.trim()||b.body.length>2000||typeof b.request_id!=="string"||!uuid.test(b.request_id)||typeof b.expected_updated_at!=="string"||!Number.isFinite(Date.parse(b.expected_updated_at)))return NextResponse.json({error:"Revisa el mensaje y actualiza la conversación."},{status:400});
  return NextResponse.json(await rpc("olivia_manual_reply",{p_conversation:id,p_body:b.body.trim(),p_request:b.request_id,p_expected_updated_at:b.expected_updated_at,p_actor:user.id}));
 }catch(e){const error=e instanceof Error?e.message:"No se pudo añadir el mensaje a la cola.";return NextResponse.json({error},{status:error.includes("conversación ha cambiado")?409:400});}
}
