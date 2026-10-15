import { NextResponse } from "next/server";
import { isAdmin } from "../../../lib/auth";
import { select } from "../../../lib/supabase";

export async function GET() {
  if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });
  try {
    const [products, contacts, conversations, documents, touchpoints] = await Promise.all([
      select<any>("catalog_products", "select=id,name,price,stock_status,image_url,internal_notes,manual_tags,permalink&order=name.asc&limit=100"),
      select<any>("contacts", "select=id&limit=1000"),
      select<any>("conversations", "select=id,status&limit=1000"),
      select<any>("product_documents", "select=id&limit=1000"),
      select<any>("attribution_touchpoints", "select=id&limit=1000")
    ]);
    return NextResponse.json({
      products,
      metrics: {
        products: products.length,
        contacts: contacts.length,
        openConversations: conversations.filter((item: { status: string }) => item.status === "open").length,
        inStock: products.filter((item: { stock_status: string }) => item.stock_status === "instock").length
      },
      documents: documents.length,
      touchpoints: touchpoints.length
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Error de lectura" }, { status: 500 });
  }
}
