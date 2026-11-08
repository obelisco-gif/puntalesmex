const assert=require('node:assert/strict');
const ops=require('../n8n/agent-document-selection.json');
const code=ops.find(o=>o.nodeName==='Preparar respuesta con decisión').parameters.jsCode;
const execute=new Function('$','$json',code);
const ctx={batch_text:'¿Cómo preparo el producto?',contact:{first_name:'Demo',tags:[]},history:[],products:[{id:'product-a'}],document_index:[
{id:'usage-a',packages:['usage']},{id:'bf',packages:['black_friday']},{id:'own',packages:['orchestrator']},{id:'voice',packages:['always']},{id:'private',packages:['internal_ops']},{id:'stop',packages:['opt_out']}],conversation:{handoff_status:'bot'}};
const run=(raw,c=ctx)=>execute(()=>({item:{json:{output:raw}}}),{context:c}).json.decision;
let d=run({intent:'product',selected_document_ids:['usage-a','usage-a','bf','own','voice','private','inventado'],knowledge_packages:['usage','black_friday','orchestrator'],product_ids:['product-a','wrong'],pending_question:''});
assert.deepEqual(d.selected_document_ids,['usage-a','bf']);
assert.deepEqual(d.knowledge_packages,['usage','black_friday']);
assert.deepEqual(d.product_ids,['product-a']);
d=run({intent:'opt_out',selected_document_ids:['usage-a','bf','stop'],knowledge_packages:['usage'],product_ids:['product-a']},{...ctx,batch_text:'STOP'});
assert.deepEqual(d.selected_document_ids,['stop']);assert.deepEqual(d.product_ids,[]);
d=run({intent:'early_access',early_access_action:'offer_registration',selected_document_ids:['bf'],knowledge_packages:['black_friday'],pending_question:'¿Te apunto al acceso prioritario al Black Friday?'},{...ctx,batch_text:'Alguna oferta'});
assert.equal(d.pending_question,'¿Te apunto al acceso prioritario al Black Friday?');assert.deepEqual(d.selected_document_ids,['bf']);
const schema=JSON.parse(ops.find(o=>o.nodeName==='Decisión estructurada').parameters.inputSchema);
assert.ok(schema.required.includes('selected_document_ids'));assert.equal(schema.properties.selected_document_ids.maxItems,8);
console.log('PASS: exact ID selection, unknown/internal/router exclusions, campaign selectable, STOP isolation and full schema.');
