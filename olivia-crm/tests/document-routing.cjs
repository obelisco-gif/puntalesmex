const assert = require("node:assert/strict");
const ops = require("../n8n/document-routing.json");
const code = ops.find(op=>op.nodeName==="Preparar respuesta con decisión").parameters.jsCode;
const run = new Function("$","$json",code);
const context = {batch_text:"¿Cómo conservo este producto?",contact:{tags:[]},products:[{id:"product-a"}],document_index:[{packages:["storage","tema_nuevo"]},{packages:["internal_ops","always","black_friday"]}]};
function decide(output,ctx=context){return run(()=>({item:{json:ctx}}),{output}).json.decision;}
const choice=decide({intent:"product",knowledge_packages:["storage","tema_nuevo","inventado","internal_ops"],product_ids:["product-a","not-in-catalog"]});
assert.deepEqual(choice.knowledge_packages,["storage","tema_nuevo"]);
assert.deepEqual(choice.product_ids,["product-a"]);
assert.deepEqual(decide({intent:"product",knowledge_packages:["always","black_friday","internal_ops"],product_ids:[]}).knowledge_packages,[]);
const stop=decide({intent:"product",knowledge_packages:["storage"],product_ids:["product-a"]},{...context,batch_text:"STOP"});
assert.equal(stop.opt_out,true);
assert.deepEqual(stop.knowledge_packages,["opt_out"]);
assert.deepEqual(stop.product_ids,[]);
console.log("PASS: custom document topics, unknown/internal topic rejection, catalog product validation and STOP context isolation.");
