import { NextResponse } from "next/server";
import { isAdmin } from "../../../lib/auth";
import { select } from "../../../lib/supabase";

export async function GET() {
  if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });

  try {
    const [products, contacts, conversations, messages, documents, touchpoints] = await Promise.all([
      select<any>("catalog_products", "select=id,name,price,stock_status,image_url,internal_notes,manual_tags,permalink&order=name.asc&limit=100"),
      select<any>("contacts", "select=id,first_name,email,phone,stage,source,manual_tags,internal_notes,preferences,assigned_to,updated_at&order=updated_at.desc&limit=100"),
      select<any>("conversations", "select=id,contact_id,channel,status,priority,handoff_status,internal_notes,updated_at,contacts(first_name,email,phone)&order=updated_at.desc&limit=100"),
      select<any>("messages", "select=id,conversation_id,direction,body,external_message_id,created_at&order=created_at.asc&limit=1000"),
      select<any>("product_documents", "select=id,catalog_product_id,document_type,title,content,source_url,approval_status,reviewed_at,updated_at&order=updated_at.desc&limit=100"),
      select<any>("attribution_touchpoints", "select=id,contact_id,channel,source,campaign,medium,content,external_lead_id,occurred_at,metadata,contacts(first_name,email,phone)&order=occurred_at.desc&limit=100")
    ]);

    return NextResponse.json({
      products,
      contacts,
      conversations,
      messages,
      documents,
      touchpoints,
      metrics: {
        products: products.length,
        contacts: contacts.length,
        openConversations: conversations.filter((item: { status: string }) => item.status === "open").length,
        inStock: products.filter((item: { stock_status: string }) => item.stock_status === "instock").length
      }
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Error de lectura" }, { status: 500 });
  }
}
