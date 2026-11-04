const http = require("node:http");
const { spawn } = require("node:child_process");
const assert = require("node:assert/strict");
const { once } = require("node:events");

async function main() {
  const email = "admin@example.invalid";
  const user = { id: "00000000-0000-4000-8000-000000000001", aud: "authenticated", role: "authenticated", email, email_confirmed_at: new Date().toISOString(), app_metadata: { provider: "email", providers: ["email"] }, user_metadata: {}, created_at: new Date().toISOString() };
  const token = [Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url"), Buffer.from(JSON.stringify({ sub: user.id, exp: Math.floor(Date.now()/1000)+3600, iat: Math.floor(Date.now()/1000), aud: "authenticated", email, role: "authenticated" })).toString("base64url"), "test-signature"].join(".");
  let active = false, emails = 0, updates = 0, documentWrites = 0, savedDocument = null, contactWrites = 0, entryWrites = 0;
  const provider = http.createServer(async (req, res) => {
    let raw = ""; for await (const chunk of req) raw += chunk;
    const body = raw ? JSON.parse(raw) : {};
    res.setHeader("content-type", "application/json");
    if (req.url.startsWith("/auth/v1/token")) {
      if (!(body.email === email && body.password === "test-only-password") && body.auth_code !== "valid-code") {
        res.statusCode = 400; return res.end(JSON.stringify({ error: "invalid_grant", error_description: "Invalid credentials" }));
      }
      active = true;
      return res.end(JSON.stringify({ access_token: token, refresh_token: "test-refresh", token_type: "bearer", expires_in: 3600, user }));
    }
    if (req.url.startsWith("/auth/v1/recover")) { emails++; return res.end("{}"); }
    if (req.url.startsWith("/auth/v1/user")) {
      if (!active || req.headers.authorization !== "Bearer " + token) { res.statusCode = 401; return res.end(JSON.stringify({ msg: "Unauthorized" })); }
      if (req.method === "PUT") updates++;
      return res.end(JSON.stringify(user));
    }
    if (req.url.startsWith("/auth/v1/logout")) { active = false; res.statusCode = 204; return res.end(); }
    if (req.url.startsWith("/rest/v1/rpc/save_olivia_document")) {
      documentWrites++;
      savedDocument = { ...body.p_document, id: body.p_id || "00000000-0000-4000-8000-000000000010", updated_at: new Date().toISOString() };
      return res.end(JSON.stringify(savedDocument));
    }
    if (req.url.startsWith("/rest/v1/rpc/olivia_save_contact")) { contactWrites++; return res.end(JSON.stringify(body.p_input)); }
    if (req.url.startsWith("/rest/v1/rpc/olivia_save_commercial_entry")) { entryWrites++; return res.end(JSON.stringify(body.p_entry)); }
    if (req.url.startsWith("/rest/v1/product_documents")) return res.end(JSON.stringify(savedDocument ? [{
      ...savedDocument, product_document_products: savedDocument.catalog_product_ids.map(catalog_product_id => ({catalog_product_id}))
    }] : []));
    if (req.url.startsWith("/rest/v1/")) return res.end("[]");
    res.statusCode = 404; res.end("{}");
  });
  provider.listen(0, "127.0.0.1"); await once(provider, "listening");
  const socket = http.createServer(); socket.listen(0, "127.0.0.1"); await once(socket, "listening");
  const port = socket.address().port; await new Promise(resolve => socket.close(resolve));
  const base = "http://localhost:" + port;
  const child = spawn(process.execPath, ["node_modules/next/dist/bin/next", "start", "-p", String(port)], { cwd: process.cwd(), env: { ...process.env, SUPABASE_URL: "http://127.0.0.1:" + provider.address().port, SUPABASE_PUBLISHABLE_KEY: "test-public", SUPABASE_SERVICE_ROLE_KEY: "test-service-not-real", CRM_ADMIN_EMAILS: email, CRM_SITE_URL: base, NEXT_TELEMETRY_DISABLED: "1" }, stdio: ["ignore", "pipe", "pipe"] });
  let logs = ""; child.stdout.on("data", c => logs += c); child.stderr.on("data", c => logs += c);
  const jar = new Map();
  async function request(path, method = "GET", body, headers = {}) {
    const response = await fetch(base + path, { method, headers: { origin: base, cookie: [...jar].map(([k,v]) => k+"="+v).join("; "), ...(body ? { "content-type": "application/json" } : {}), ...headers }, body: body ? JSON.stringify(body) : undefined, redirect: "manual" });
    for (const cookie of response.headers.getSetCookie()) { const [pair] = cookie.split(";"); const pos = pair.indexOf("="); jar.set(pair.slice(0,pos),pair.slice(pos+1)); }
    return response;
  }
  try {
    for (let i=0;i<100;i++) { try { await fetch(base); break; } catch { await new Promise(r=>setTimeout(r,100)); } }
    assert.equal((await request("/api/dashboard")).status,401);
    jar.set("olivia_crm_session","old-shared-password-cookie");
    assert.equal((await request("/api/dashboard")).status,401,"legacy cookie must not grant access");
    assert.equal((await request("/api/session","POST",{email:"outsider@example.invalid",password:"anything"})).status,401);
    assert.equal((await request("/api/session","POST",{email,password:"wrong"})).status,401);
    assert.equal((await request("/api/session","POST",{email,password:"test-only-password"},{origin:"https://attacker.invalid"})).status,403);
    assert.equal((await request("/api/auth/password","POST",{password:"new-test-only-password"})).status,401);
    assert.equal((await request("/api/auth/recover","POST",{email:"outsider@example.invalid"})).status,200);
    assert.equal(emails,0,"must not send outside allowlist");
    assert.equal((await request("/api/auth/recover","POST",{email})).status,200);
    assert.equal(emails,1);
    assert.equal((await request("/auth/callback?code=valid-code&next=%2Freset-password")).headers.get("location"),base+"/reset-password");
    assert.equal((await request("/api/dashboard")).status,200,"verified allowlisted session reads CRM");
    const document = { title:"Guía conjunta",content:"Contenido de prueba",approval_status:"draft",routing_packages:["commercial","black_friday","tema_nuevo"],catalog_product_ids:["00000000-0000-4000-8000-000000000002","00000000-0000-4000-8000-000000000003"],source_url:"https://example.invalid/fuente" };
    const created = await request("/api/documents","POST",document);
    assert.equal(created.status,201);
    const createdDocument = await created.json();
    assert.deepEqual(createdDocument.catalog_product_ids,document.catalog_product_ids);
    assert.deepEqual(createdDocument.routing_packages,document.routing_packages);
    const dashboard = await (await request("/api/dashboard")).json();
    assert.deepEqual(dashboard.documents[0].catalog_product_ids,document.catalog_product_ids,"read relation links into editor");
    assert.equal((await request("/api/crm/documents/"+createdDocument.id,"PATCH",{...document,approval_status:"approved",catalog_product_ids:[document.catalog_product_ids[1]]})).status,200);
    assert.equal(savedDocument.approval_status,"approved");
    assert.equal(savedDocument.catalog_product_ids.length,1);
    assert.equal((await request("/api/documents","POST",{...document,catalog_product_ids:["invalid-id"]})).status,400);
    assert.equal((await request("/api/documents","POST",{...document,source_url:"javascript:alert(1)"})).status,400);
    assert.equal((await request("/api/documents","POST",{...document,routing_packages:["always"]})).status,400,"permanent base must be general");
    assert.equal((await request("/api/crm/documents/"+createdDocument.id,"PATCH",{...document,routing_packages:[]})).status,400);
    assert.equal(documentWrites,2,"invalid documents must never reach database");
    const contactPath = "/api/crm/contacts/00000000-0000-4000-8000-000000000020";
    const contact = {stage:"purchase_intent",manual_tags:["bf2026_early_access"],expected_updated_at:new Date().toISOString(),commercial:{tastes:"Canela",objections:"Sin jengibre",buying_horizon:"Este mes",score_override:82}};
    assert.equal((await request(contactPath,"PATCH",contact)).status,200);
    assert.equal((await request(contactPath,"PATCH",{...contact,stage:"lead"})).status,400);
    assert.equal((await request(contactPath,"PATCH",{...contact,commercial:{...contact.commercial,score_override:101}})).status,400);
    assert.equal((await request(contactPath,"PATCH",contact,{origin:"https://attacker.invalid"})).status,403);
    assert.equal(contactWrites,1);
    const entryPath = "/api/crm/contact_entries/00000000-0000-4000-8000-000000000020";
    const entry = {kind:"purchase",reference:"QA-123",details:"Compra comprobada",status:"confirmed",amount:19.99,quantity:1,occurred_on:"2026-11-04"};
    assert.equal((await request(entryPath,"PATCH",entry)).status,200);
    assert.equal((await request(entryPath,"PATCH",{...entry,reference:""})).status,400);
    assert.equal((await request(entryPath,"PATCH",{...entry,amount:-1})).status,400);
    assert.equal((await request(entryPath,"PATCH",{...entry,kind:"interest"})).status,400);
    assert.equal(entryWrites,1);
    assert.equal((await request("/api/documents","POST",document,{origin:"https://attacker.invalid"})).status,403);
    assert.equal((await request("/api/auth/password","POST",{password:"short"})).status,400);
    assert.equal((await request("/api/auth/password","POST",{password:"new-test-only-password"})).status,200);
    assert.equal(updates,1);
    assert.equal((await request("/api/session","DELETE")).status,200);
    assert.equal((await request("/api/dashboard")).status,401,"logout must revoke access");
    assert.equal((await request(contactPath,"PATCH",contact)).status,401);
    assert.equal((await request(entryPath,"PATCH",entry)).status,401);
    assert.equal((await request("/api/session","POST",{email,password:"test-only-password"})).status,200);
    assert.equal((await request("/api/dashboard")).status,200);
    active = false;
    assert.equal((await request("/api/dashboard")).status,401,"revoked provider session must fail closed");
    console.log("PASS: auth boundaries, document create/edit/read with multiple products and custom topics, validation, CSRF, recovery, password update, logout and revocation.");
  } catch (error) { console.error(logs.slice(-3000)); throw error; }
  finally { child.kill(); await new Promise(resolve => provider.close(resolve)); }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
