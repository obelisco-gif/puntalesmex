import { NextResponse } from "next/server";
import { isAdmin } from "../../../lib/auth";
import { count, rpc } from "../../../lib/supabase";

type PurchaseStats = { with_prior_purchase: number; without_identified_prior_purchase: number; unknown_registration_date: number };
type SourceStats = { meta_form: number; web_form: number; both_forms: number; other_or_unknown: number };

export async function GET() {
  if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });
  const tagged = "select=id&manual_tags=cs.%7Bbf2026_early_access%7D&or=(source.is.null,source.neq.qa_test)";
  try {
    const [total, email, phone, both, purchases, sources] = await Promise.all([
      count("contacts", tagged),
      count("contacts", tagged + "&email=not.is.null&email=neq."),
      count("contacts", tagged + "&phone=not.is.null&phone=neq."),
      count("contacts", tagged + "&email=not.is.null&email=neq.&phone=not.is.null&phone=neq."),
      rpc<PurchaseStats>("olivia_early_access_purchase_stats", {}),
      rpc<SourceStats>("olivia_early_access_source_stats", {})
    ]);
    return NextResponse.json({ total, email, phone, both, ...purchases, ...sources });
  } catch {
    return NextResponse.json({ error: "No se pudieron cargar las estadísticas." }, { status: 500 });
  }
}
