import { NextResponse } from "next/server";
import { isAdmin } from "../../../lib/auth";
import { select, rpc } from "../../../lib/supabase";

export async function GET() {
  if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });

  try {
    const [products, contacts, directory, documents, touchpoints, attributionPanels] = await Promise.all([
      rpc<any[]>("olivia_catalog_products", {}),
      rpc<{total:number}>("olivia_contact_directory", {p_page:1,p_search:"",p_stage:"",p_tag:""}),
      rpc<{open_total:number}>("olivia_conversation_directory", {p_page:1,p_search:"",p_status:"",p_control:""}),
      select<any>("product_documents", "select=id,catalog_product_id,document_type,title,content,source_url,approval_status,reviewed_at,updated_at,routing_packages,product_document_products(catalog_product_id)&order=updated_at.desc&limit=100"),
      select<any>("attribution_touchpoints", "select=id,contact_id,channel,source,campaign,medium,content,external_lead_id,occurred_at,metadata,contacts(first_name,email,phone)&order=occurred_at.desc&limit=100"),
      rpc<any>("olivia_attribution_panels", {})
    ]);

    return NextResponse.json({
      products,
      documents: documents.map((document: any) => ({
        ...document,
        catalog_product_ids: [...new Set([...(document.product_document_products || []).map((link: any) => link.catalog_product_id), ...(document.catalog_product_id ? [document.catalog_product_id] : [])])]
      })),
      touchpoints,
      attributionPanels: attributionPanels || { early_access: [], purchases: [] },
      metrics: {
        products: products.length,
        contacts: contacts.total || 0,
        openConversations: directory.open_total || 0,
        inStock: products.filter((item: { stock_status: string }) => item.stock_status === "instock").length
      }
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Error de lectura" }, { status: 500 });
  }
}
