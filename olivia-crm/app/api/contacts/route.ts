import { NextRequest, NextResponse } from "next/server";
import { isAdmin } from "../../../lib/auth";
import { rpc } from "../../../lib/supabase";
import { registrationSources, type RegistrationSource } from "../../../lib/registration-sources";
const stages=["","new","engaged","qualified","recommended","purchase_intent","customer","on_hold","lost","unsubscribed"];
export async function GET(request:NextRequest){
 if(!(await isAdmin()))return NextResponse.json({error:"No autorizado"},{status:401});
 const p=request.nextUrl.searchParams,page=Number(p.get("page")||1),stage=p.get("stage")||"",tag=p.get("tag")||"";
 if(!Number.isSafeInteger(page)||page<1||page>100000||!stages.includes(stage)||tag.length>80)return NextResponse.json({error:"Filtros no válidos"},{status:400});
 try{const result=await rpc<{rows:{id:string;registration_sources?:RegistrationSource[]}[];[key:string]:unknown}>("olivia_contact_directory",{p_page:page,p_search:(p.get("q")||"").trim().slice(0,100),p_stage:stage,p_tag:tag});const origins=await registrationSources(result.rows.map(row=>row.id));result.rows=result.rows.map(row=>({...row,registration_sources:origins[row.id]||[]}));return NextResponse.json(result);}
 catch{return NextResponse.json({error:"No se pudieron cargar los contactos."},{status:500});}
}
