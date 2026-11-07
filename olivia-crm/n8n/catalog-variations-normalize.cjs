// Pure function shared by the n8n Code node and local pagination tests.
function normalizeVariationSnapshots(items, seedAt) {
 const grouped=new Map();
 const money=value=>{if(value==null||value==='')return null;const n=Number(value);if(!Number.isFinite(n)||n<0)throw new Error('Precio no válido');return n;};
 const date=value=>{if(!value)return null;const s=/Z$|[+-]\d{2}:\d{2}$/.test(value)?value:value+'Z';if(!Number.isFinite(Date.parse(s)))throw new Error('Fecha no válida');return new Date(s).toISOString();};
 items.forEach((item,index)=>{
  const seed=seedAt(index);const id=Number(seed.woocommerce_product_id);
  if(!Number.isSafeInteger(id)||id<1||!seed.catalog_product_id||!Array.isArray(seed.expected_ids))throw new Error('Falta correlación con el producto padre');
  if(!grouped.has(id))grouped.set(id,{catalog_product_id:seed.catalog_product_id,woocommerce_product_id:id,requested_at:seed.requested_at,expected_ids:seed.expected_ids,complete:true,variations:[],pages:0});
  const snapshot=grouped.get(id),body=item.json.body??item.json;
  if(!Array.isArray(body))throw new Error('Respuesta de variantes no válida');snapshot.pages++;
  for(const v of body){
   if(!Number.isSafeInteger(Number(v.id))||Number(v.id)<1)throw new Error('ID de variante no válido');
   const attributes=(v.attributes||[]).map(a=>({id:a.id,name:String(a.name||''),option:String(a.option??'')}));
   const quantity=v.stock_quantity==null?null:Number(v.stock_quantity);if(quantity!==null&&!Number.isSafeInteger(quantity))throw new Error('Cantidad de stock no válida');
   const label=attributes.map(a=>a.option||'Cualquier '+a.name).join(' · ');
   snapshot.variations.push({woocommerce_variation_id:Number(v.id),sku:String(v.sku||''),name:label||'Variante '+v.id,status:v.status||'publish',price:money(v.price),regular_price:money(v.regular_price),sale_price:money(v.sale_price),on_sale:v.on_sale===true,purchasable:v.purchasable===true,stock_status:['instock','outofstock','onbackorder'].includes(v.stock_status)?v.stock_status:'unknown',stock_quantity:quantity,manage_stock:typeof v.manage_stock==='boolean'?v.manage_stock:null,attributes,image_url:v.image?.src||null,permalink:v.permalink||null,source_modified_at:date(v.date_modified_gmt)});
  }
 });
 return [...grouped.values()].map(snapshot=>{
  const actual=snapshot.variations.map(v=>v.woocommerce_variation_id).sort((a,b)=>a-b),expected=snapshot.expected_ids.map(Number).sort((a,b)=>a-b);
  if(new Set(actual).size!==actual.length||JSON.stringify(actual)!==JSON.stringify(expected))throw new Error('Instantánea incompleta o producto modificado durante la consulta: '+snapshot.woocommerce_product_id);
  return {json:snapshot};
 });
}
if(typeof module!=='undefined')module.exports={normalizeVariationSnapshots};
