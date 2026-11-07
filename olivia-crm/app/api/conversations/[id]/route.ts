import { NextRequest, NextResponse } from "next/server";
import { isAdmin } from "../../../../lib/auth";
import { rpc } from "../../../../lib/supabase";
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function GET(request:NextRequest,context:{params:Promise<{id:string}>}) {
 if (!(await isAdmin())) return NextResponse.json({error:"No autorizado"},{status:401});
 const {id}=await context.params, before=request.nextUrl.searchParams.get("before");
 if (!uuid.test(id)||(before!==null&&!uuid.test(before))) return NextResponse.json({error:"Identificador no válido"},{status:400});
 try {
  const result=await rpc("olivia_conversation_detail",{p_id:id,p_before:before});
  return result?NextResponse.json(result):NextResponse.json({error:"Conversación no encontrada"},{status:404});
 }catch{return NextResponse.json({error:"No se pudo cargar la conversación."},{status:500});}
}
