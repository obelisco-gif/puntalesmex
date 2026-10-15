import crypto from "node:crypto";
import { cookies } from "next/headers";

const cookieName = "olivia_crm_session";

function signature() {
  const password = process.env.CRM_ACCESS_PASSWORD;
  const secret = process.env.CRM_SESSION_SECRET;
  if (!password || !secret) throw new Error("Faltan las variables privadas del CRM.");
  return crypto.createHmac("sha256", secret).update(password).digest("hex");
}

export async function isAdmin() {
  return (await cookies()).get(cookieName)?.value === signature();
}

export async function requireAdmin() {
  if (!(await isAdmin())) throw new Error("UNAUTHORIZED");
}

export async function createSession() {
  (await cookies()).set(cookieName, signature(), { httpOnly: true, sameSite: "lax", secure: process.env.NODE_ENV === "production", path: "/", maxAge: 60 * 60 * 12 });
}

export async function clearSession() {
  (await cookies()).delete(cookieName);
}
