import { NextRequest, NextResponse } from "next/server";
import { isAdmin } from "../../../lib/auth";
import { rpc } from "../../../lib/supabase";

export async function GET(request: NextRequest) {
  if (!(await isAdmin())) return NextResponse.json({error:"No autorizado"},{status:401});
  const p=request.nextUrl.searchParams, page=Number(p.get("page")||1);
  const status=p.get("status")||"", control=p.get("control")||"";
  if (!Number.isSafeInteger(page)||page<1||page>100000||!["","open","paused","closed"].includes(status)||!["","bot","human","pending_human","resolved"].includes(control)) return NextResponse.json({error:"Filtros no válidos"},{status:400});
  try { return NextResponse.json(await rpc("olivia_conversation_directory",{p_page:page,p_search:(p.get("q")||"").trim().slice(0,100),p_status:status,p_control:control})); }
  catch { return NextResponse.json({error:"No se pudieron cargar las conversaciones."},{status:500}); }
}
