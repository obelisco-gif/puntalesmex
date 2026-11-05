const {PGlite}=require('@electric-sql/pglite');
const fs=require('node:fs');
const path=require('node:path');
async function main(){
 const db=new PGlite();
 try{
  await db.exec(fs.readFileSync('tests/fixtures-base.sql','utf8'));
  await db.exec(fs.readFileSync('tests/fixtures-catalog.sql','utf8'));
  const original=fs.readFileSync('tests/fixtures-core.sql','utf8');
  // Core functions and jobs; the original ingress integration is outside these tests.
  await db.exec(original);
  for(const file of ['database/document-relations.sql','database/commercial-contact.sql','database/conversation-actions.sql','database/commercial-context.sql','database/agent-attributes.sql','database/agent-attributes-context.sql','database/woo-orders.sql','database/woo-orders-context.sql','database/conversation-workspace.sql','database/manual-replies.sql','database/contact-directory.sql','database/handoffs.sql','database/handoff-outbound.sql','database/ai-disclosure.sql','database/ai-disclosure-outbound.sql','database/ai-disclosure-claim.sql','database/catalog-variations.sql','database/catalog-parent-sync.sql','database/catalog-variations-context.sql','database/dispatcher-producer.sql','database/dispatcher-customer.sql','database/dispatcher-claim.sql','database/dispatcher-runtime.sql','database/dispatcher-repair.sql','database/meta-sheet-policy.sql','database/ai-notice-generated-replies.sql','database/welcome-template-name.sql']){
   try{await db.exec(fs.readFileSync(file,'utf8'));}catch(e){throw new Error(file+': '+e.message,{cause:e});}
  }
  await db.exec("insert into public.catalog_products(woocommerce_product_id,name,price,permalink) values(10,'Colágeno marino Peptan® - Aroma naranja - 500g',42.50,'https://example.invalid/colageno');");
  for(const file of ['tests/commercial-contact.sql','tests/agent-attributes.sql','tests/woo-orders.sql','tests/conversation-workspace.sql','tests/manual-replies.sql','tests/contact-directory.sql','tests/handoffs.sql','tests/ai-disclosure.sql','tests/catalog-variations.sql','tests/dispatcher.sql','tests/meta-sheet-policy.sql','tests/ai-notice-generated-replies.sql','tests/welcome-template-name.sql']){
   try{const result=await db.exec(fs.readFileSync(file,'utf8'));console.log(file+': '+result.flatMap(r=>r.rows??[]).map(r=>r.result).filter(Boolean).join(' '));}catch(e){throw new Error(file+': '+e.message,{cause:e});}
  }
  console.log('PASS: disposable local PostgreSQL; no remote database or external messages.');
 }finally{await db.close();}
}
main().catch(e=>{console.error(e.message);console.error(e.cause?.where??'');process.exitCode=1;});
