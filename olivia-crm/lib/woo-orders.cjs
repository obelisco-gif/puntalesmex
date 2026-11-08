// Pure normalization shared by the n8n import and its local tests.
function normalizePhone(value,country='') {
 let digits=String(value??'').replace(/\D/g,'');
 if(digits.startsWith('00'))digits=digits.slice(2);
 if(country.toUpperCase()==='ES'&&/^[6789]\d{8}$/.test(digits))digits='34'+digits;
 return /^[1-9]\d{9,14}$/.test(digits)?'+'+digits:null;
}
function utc(value,required=false) {
 if(!value){if(required)throw new Error('Falta fecha GMT de WooCommerce');return null;}
 const source=String(value),iso=/Z$|[+-]\d{2}:\d{2}$/.test(source)?source:source+'Z';
 if(!Number.isFinite(Date.parse(iso)))throw new Error('Fecha de pedido no válida');
 return new Date(iso).toISOString();
}
function normalizeOrder(source) {
 const integer=(v,label)=>{if(!Number.isSafeInteger(Number(v))||Number(v)<1)throw new Error(label+' no válido');return Number(v);};
 const money=v=>{const n=Number(v??0);if(!Number.isFinite(n)||n<0||n>9999999999.99)throw new Error('Importe no válido');return Math.round(n*100)/100;};
 if(!/^[a-z][a-z0-9-]{0,60}$/.test(source.status??''))throw new Error('Estado de pedido no válido');
 if(!/^[A-Z]{3}$/.test(source.currency??''))throw new Error('Moneda no válida');
 const email=String(source.billing?.email??'').trim().toLowerCase();
 const refunds=(source.refunds??[]).reduce((sum,r)=>sum+Math.abs(Number(r.total??0)),0);
 return {id:integer(source.id,'Pedido'),order_number:String(source.number??source.id).slice(0,100),customer_id:Number(source.customer_id)||null,status:source.status,
  billing_email:/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)?email:null,billing_phone:normalizePhone(source.billing?.phone,source.billing?.country??''),billing_country:String(source.billing?.country??'').slice(0,2),billing_first_name:String(source.billing?.first_name??'').trim().slice(0,100),currency:source.currency,total:money(source.total),refunded_total:money(refunds),created_at_woo:utc(source.date_created_gmt,true),source_modified_at:utc(source.date_modified_gmt,true),paid_at:utc(source.date_paid_gmt),
  items:(source.line_items??[]).map(i=>({line_id:integer(i.id,'Línea'),product_id:Number(i.product_id)||null,variation_id:Number(i.variation_id)||null,name:String(i.name??'Producto sin nombre').slice(0,300),quantity:integer(i.quantity,'Cantidad'),total:money(i.total)}))};
}
module.exports={normalizePhone,utc,normalizeOrder};
