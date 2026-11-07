import { NextRequest, NextResponse } from "next/server";
import { isAdmin } from "../../../lib/auth";
import { rpc } from "../../../lib/supabase";
export async function GET(request:NextRequest){
 if(!(await isAdmin()))return NextResponse.json({error:"No autorizado"},{status:401});
 const p=request.nextUrl.searchParams,page=Number(p.get("page")||1),status=p.get("status")||"";
 if(!Number.isSafeInteger(page)||page<1||page>100000||!["","requested","active","resolved","cancelled"].includes(status))return NextResponse.json({error:"Filtros no válidos"},{status:400});
 try{return NextResponse.json(await rpc("olivia_handoff_directory",{p_page:page,p_status:status,p_search:(p.get("q")||"").trim().slice(0,100)}));}
 catch{return NextResponse.json({error:"No se pudieron cargar las derivaciones."},{status:500});}
}
