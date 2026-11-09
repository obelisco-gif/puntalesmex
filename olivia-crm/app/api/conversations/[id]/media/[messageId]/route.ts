import { NextRequest, NextResponse } from "next/server";
import { isAdmin } from "../../../../../../lib/auth";
import { rpc } from "../../../../../../lib/supabase";

type Attachment = { type: string; mime_type: string; data: string };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const safe = /^(image\/(jpeg|png|webp|gif)|audio\/(ogg|mpeg|mp4|aac|amr)|video\/(mp4|3gpp)|application\/(pdf|msword|vnd\.ms-excel|vnd\.openxmlformats-officedocument\.wordprocessingml\.document|vnd\.openxmlformats-officedocument\.spreadsheetml\.sheet)|text\/plain)$/;

export async function GET(_request: NextRequest, context: { params: Promise<{ id: string; messageId: string }> }) {
 if (!(await isAdmin())) return NextResponse.json({ error: "No autorizado" }, { status: 401 });
 const { id, messageId } = await context.params;
 if (!uuid.test(id) || !uuid.test(messageId)) return NextResponse.json({ error: "Identificador no válido" }, { status: 400 });
 try {
  const item = await rpc<Attachment | null>("olivia_read_message_attachment", { p_conversation_id: id, p_message_id: messageId });
  if (!item || !safe.test(item.mime_type)) return NextResponse.json({ error: "Adjunto no disponible" }, { status: 404 });
  return new NextResponse(Buffer.from(item.data, "base64"), { headers: { "Content-Type": item.mime_type, "Content-Disposition": item.type === "document" ? "attachment" : "inline", "X-Content-Type-Options": "nosniff", "Content-Security-Policy": "default-src 'none'; sandbox", "Cache-Control": "private, no-store" } });
 } catch { return NextResponse.json({ error: "No se pudo cargar el adjunto" }, { status: 500 }); }
}
