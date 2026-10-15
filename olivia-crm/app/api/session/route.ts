import { NextResponse } from "next/server";
import { clearSession, createSession } from "../../../lib/auth";

export async function POST(request: Request) {
  const { password } = await request.json();
  if (!process.env.CRM_ACCESS_PASSWORD || password !== process.env.CRM_ACCESS_PASSWORD) {
    return NextResponse.json({ error: "No autorizado" }, { status: 401 });
  }
  await createSession();
  return NextResponse.json({ ok: true });
}

export async function DELETE() {
  await clearSession();
  return NextResponse.json({ ok: true });
}
