import { NextResponse } from "next/server";
import { isAdmin } from "../../../../lib/auth";
import { rpc } from "../../../../lib/supabase";
export async function GET(_request:Request,context:{params:Promise<{id:string}>}){
 if(!(await isAdmin()))return NextResponse.json({error:"No autorizado"},{status:401});
 const {id}=await context.params;
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))return NextResponse.json({error:"Identificador no válido"},{status:400});
 try{const contact=await rpc("olivia_contact_detail",{p_id:id});return contact?NextResponse.json(contact):NextResponse.json({error:"Contacto no encontrado"},{status:404});}
 catch{return NextResponse.json({error:"No se pudo cargar la ficha."},{status:500});}
}
