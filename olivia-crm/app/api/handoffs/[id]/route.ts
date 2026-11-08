import { NextRequest, NextResponse } from "next/server";
import { adminUser, sameOrigin } from "../../../../lib/auth";
import { rpc } from "../../../../lib/supabase";
export async function PATCH(request:NextRequest,context:{params:Promise<{id:string}>}){
 if(!sameOrigin(request))return NextResponse.json({error:"Origen no permitido"},{status:403});
 const user=await adminUser();if(!user)return NextResponse.json({error:"No autorizado"},{status:401});
 const {id}=await context.params;
 try{
  const b=await request.json();
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)||!["requested","active","resolved","cancelled"].includes(b.status)||typeof b.assigned_to!=="string"||b.assigned_to.length>100||typeof b.internal_notes!=="string"||b.internal_notes.length>10000||typeof b.expected_updated_at!=="string"||!Number.isFinite(Date.parse(b.expected_updated_at)))return NextResponse.json({error:"Revisa los datos de la derivación."},{status:400});
  return NextResponse.json(await rpc("olivia_save_handoff",{p_id:id,p_input:{status:b.status,assigned_to:b.assigned_to,internal_notes:b.internal_notes,expected_updated_at:b.expected_updated_at},p_actor:user.id}));
 }catch(e){const message=e instanceof Error?e.message:"No se pudo guardar.";return NextResponse.json({error:message},{status:message.includes("derivación ha cambiado")?409:400});}
}
