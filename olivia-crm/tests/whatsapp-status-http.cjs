const assert=require('node:assert/strict');
const {createHmac}=require('node:crypto');
async function main(){
 const raw=' { "object": "whatsapp_business_account", "entry": [ { "id":"WABA1", "changes":[{"field":"messages","value":{"metadata":{"phone_number_id":"PHONE1"},"statuses":[{"id":"wamid.test1","status":"read","timestamp":"1767261780"}]}}]}], "nota":"café 🌿" } ';
 const signature='sha256='+createHmac('sha256','test-only-meta-secret').update(raw).digest('hex');
 const send=(body,header)=>fetch('http://127.0.0.1:3337/api/webhooks/whatsapp-status',{method:'POST',headers:{'content-type':'application/json',...(header?{'x-hub-signature-256':header}:{})},body});
 assert.equal((await send(raw,signature)).status,200);
 assert.equal((await send(raw,null)).status,401);
 assert.equal((await send(raw+' ',signature)).status,401);
 console.log('PASS: signed status accepted; missing and modified signatures rejected');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
