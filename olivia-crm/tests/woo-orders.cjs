const assert=require('node:assert/strict');
const {normalizePhone,normalizeOrder}=require('../lib/woo-orders.cjs');
assert.equal(normalizePhone('999 000 301','ES'),'+34999000301');
assert.equal(normalizePhone('0034 999 000 301'),'+34999000301');
assert.equal(normalizePhone('34999000301'),'+34999000301');
assert.equal(normalizePhone('1234'),null);
const source={id:10,number:'S-10',status:'completed',currency:'EUR',total:'29.90',date_created_gmt:'2026-10-01T10:00:00',date_modified_gmt:'2026-11-04T09:00:00',date_paid_gmt:'2026-10-01T10:01:00',billing:{email:' A@Example.invalid ',phone:'999 000 301',country:'ES',first_name:'Marta',address_1:'DO NOT IMPORT',last_name:'DO NOT IMPORT'},line_items:[{id:1,product_id:10,variation_id:20,name:'Colágeno',quantity:2,total:'29.90'}],refunds:[{total:'-5.00'}],customer_ip_address:'DO NOT IMPORT',payment_url:'DO NOT IMPORT',order_key:'DO NOT IMPORT'};
const result=normalizeOrder(source);
assert.equal(result.billing_email,'a@example.invalid');assert.equal(result.billing_phone,'+34999000301');assert.equal(result.refunded_total,5);assert.equal(result.paid_at,'2026-10-01T10:01:00.000Z');assert.equal(result.items[0].variation_id,20);assert(!JSON.stringify(result).includes('DO NOT IMPORT'));
assert.equal(normalizeOrder({...source,status:'cttexpress-sent'}).status,'cttexpress-sent');assert.throws(()=>normalizeOrder({...source,status:'bad status'}));assert.throws(()=>normalizeOrder({...source,total:'NaN'}));assert.throws(()=>normalizeOrder({...source,date_modified_gmt:null}));
console.log('PASS: WooCommerce normalization, phone/email identity, dates, refunds, variants and minimal data.');

