import { NextResponse } from "next/server";
import { isAdmin, adminUser, sameOrigin } from "../../../../lib/auth";
import { rpc } from "../../../../lib/supabase";
import { registrationSources } from "../../../../lib/registration-sources";
export async function GET(_request:Request,context:{params:Promise<{id:string}>}){
 if(!(await isAdmin()))return NextResponse.json({error:"No autorizado"},{status:401});
 const {id}=await context.params;
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))return NextResponse.json({error:"Identificador no válido"},{status:400});
 try{const contact=await rpc<Record<string,unknown>|null>("olivia_contact_detail",{p_id:id});if(!contact)return NextResponse.json({error:"Contacto no encontrado"},{status:404});const sources=await registrationSources([id]);return NextResponse.json({...contact,registration_sources:sources[id]||[]});}
 catch{return NextResponse.json({error:"No se pudo cargar la ficha."},{status:500});}
}

export async function DELETE(request:Request,context:{params:Promise<{id:string}>}){
 if(!sameOrigin(request))return NextResponse.json({error:"Origen no permitido"},{status:403});
 const user=await adminUser();if(!user)return NextResponse.json({error:"No autorizado"},{status:401});
 const {id}=await context.params;
 try{
  const body=await request.json();
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)||body.confirmation!=="ELIMINAR"||typeof body.expected_updated_at!=="string"||!Number.isFinite(Date.parse(body.expected_updated_at)))return NextResponse.json({error:"Confirma la eliminación y actualiza la ficha."},{status:400});
  return NextResponse.json(await rpc("olivia_delete_contact",{p_id:id,p_expected_updated_at:body.expected_updated_at,p_actor:user.id}));
 }catch(e){const error=e instanceof Error?e.message:"No se pudo eliminar el perfil.";return NextResponse.json({error},{status:error.includes("ha cambiado")||error.includes("en curso")?409:400});}
}
