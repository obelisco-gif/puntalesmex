// Local-only UI fixture. No live credentials, real contacts or external calls.
const http = require('node:http');
const {spawn} = require('node:child_process');
const email='admin@example.invalid';
const user={id:'00000000-0000-4000-8000-000000000001',aud:'authenticated',role:'authenticated',email,email_confirmed_at:new Date().toISOString(),app_metadata:{provider:'email',providers:['email']},user_metadata:{},created_at:new Date().toISOString()};
const token=[Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),Buffer.from(JSON.stringify({sub:user.id,exp:Math.floor(Date.now()/1000)+3600,iat:Math.floor(Date.now()/1000),aud:'authenticated',email,role:'authenticated'})).toString('base64url'),'test-signature'].join('.');
const product={id:'00000000-0000-4000-8000-000000000002',name:'Café verde con jengibre ecológico',price:14.5,stock_status:'instock',manual_tags:[],permalink:'https://example.invalid/product'};
const contact={id:'00000000-0000-4000-8000-000000000003',first_name:'Contacto de demostración',email:'demo@example.invalid',phone:'+34999000100',stage:'qualified',source:'meta_lead_form',manual_tags:['bf2026_early_access'],preferences:{commercial:{tastes:'Le gustan las infusiones con jengibre.',objections:'Prefiere evitar la canela.',buying_horizon:'Quiere reponer durante Black Friday.'},olivia:{summary:'Busca reponer café verde con jengibre. Inscrito en Early Access. Consulta el pedido DEMO-123.',pending_question:''}},assigned_to:'Equipo Sadiet',updated_at:new Date().toISOString(),score:{value:80,automatic:80,manual:false,reasons:[{reason:'Fase comercial',points:35},{reason:'Early Access',points:15},{reason:'Interés declarado en producto',points:10},{reason:'Compra confirmada en CRM',points:20}]},commercial_entries:[{id:'entry1',kind:'interest',product_id:product.id,reference:'product:'+product.id,details:'Prefiere la mezcla con jengibre.',status:'open',occurred_on:'2026-11-04',source:'conversation',evidence:'Me gusta el de jengibre'},{id:'entry2',kind:'order_inquiry',reference:'DEMO-123',details:'Solicita información del envío.',status:'open',occurred_on:'2026-11-04',source:'conversation'},{id:'entry3',kind:'purchase',reference:'DEMO-100',details:'Dos bolsas de café verde con jengibre.',status:'confirmed',amount:29,currency:'EUR',quantity:2,occurred_on:'2026-10-20',source:'crm'}]};
const provider=http.createServer(async(req,res)=>{let raw='';for await(const c of req)raw+=c;const b=raw?JSON.parse(raw):{};res.setHeader('content-type','application/json');
 if(req.url.startsWith('/auth/v1/token')){if(b.email!==email||b.password!=='test-only-password'){res.statusCode=400;return res.end('{}');}return res.end(JSON.stringify({access_token:token,refresh_token:'fake-refresh',token_type:'bearer',expires_in:3600,user}));}
 if(req.url.startsWith('/auth/v1/user'))return res.end(JSON.stringify(user));
 if(req.url.startsWith('/rest/v1/rpc/olivia_dashboard_contacts'))return res.end(JSON.stringify([contact]));
 if(req.url.startsWith('/rest/v1/catalog_products'))return res.end(JSON.stringify([product]));
 res.end('[]');
});
provider.listen(3338,'127.0.0.1',()=>{
 const child=spawn(process.execPath,['node_modules/next/dist/bin/next','start','-p','3337'],{env:{...process.env,SUPABASE_URL:'http://127.0.0.1:3338',SUPABASE_PUBLISHABLE_KEY:'fake-public',SUPABASE_SERVICE_ROLE_KEY:'fake-service',CRM_ADMIN_EMAILS:email,CRM_SITE_URL:'http://localhost:3337',NEXT_TELEMETRY_DISABLED:'1'},stdio:'inherit'});
 process.on('SIGINT',()=>{child.kill();provider.close();process.exit();});
});
