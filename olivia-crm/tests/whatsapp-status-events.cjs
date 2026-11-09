const { PGlite } = require('@electric-sql/pglite');
const fs = require('node:fs');

async function main() {
 const db = new PGlite();
 try {
  await db.exec(`
   create role anon; create role authenticated; create role service_role;
   create table public.olivia_config(key text primary key,value jsonb not null);
   create table public.outbound_dispatches(
    id uuid primary key, message_id uuid, channel text, status text,
    external_dispatch_id text, error_message text, created_at timestamptz default now()
   );
   create table public.messages(id uuid primary key,conversation_id uuid,direction text);
   insert into public.olivia_config values('bf2026','{"whatsapp_waba_id":"WABA1","whatsapp_phone_number_id":"PHONE1"}');
  `);
  await db.exec(fs.readFileSync('database/whatsapp-status-events.sql','utf8'));
  await db.exec(`
   do $test$
   declare result jsonb; inserted boolean; n integer;
   begin
    -- Receipt first: Meta can notify before the dispatch records its provider ID.
    inserted:=public.olivia_record_whatsapp_status('WABA1','PHONE1','wamid.test1','read','2026-01-01 10:03Z',null,null);
    if not inserted then raise exception 'First receipt was not inserted'; end if;
    inserted:=public.olivia_record_whatsapp_status('WABA1','PHONE1','wamid.test1','read','2026-01-01 10:03Z',null,null);
    if inserted then raise exception 'Duplicate was not ignored'; end if;
    insert into public.outbound_dispatches(id,message_id,channel,status,external_dispatch_id)
      values('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','whatsapp','pending',null);
    update public.outbound_dispatches set status='processing' where id='00000000-0000-0000-0000-000000000001';
    update public.outbound_dispatches set status='sent',external_dispatch_id='wamid.test1' where id='00000000-0000-0000-0000-000000000001';
    perform public.olivia_record_whatsapp_status('WABA1','PHONE1','wamid.test1','delivered','2026-01-01 10:02Z',null,null);
    perform public.olivia_record_whatsapp_status('WABA1','PHONE1','wamid.test1','sent','2026-01-01 10:01Z',null,null);
    result:=public.olivia_whatsapp_delivery('10000000-0000-0000-0000-000000000001');
    if result->>'status'<>'read' or (result->>'read_at')::timestamptz<>'2026-01-01 10:03Z'::timestamptz
      or (result->>'delivered_at')::timestamptz<>'2026-01-01 10:02Z'::timestamptz then raise exception 'Out-of-order result wrong: %', result; end if;
    select count(*) into n from public.olivia_whatsapp_status_events where whatsapp_message_id='wamid.test1';
    if n<>3 then raise exception 'Duplicate count wrong: %', n; end if;
    begin
     perform public.olivia_record_whatsapp_status('WRONG','PHONE1','wamid.test1','read','2026-01-01 10:03Z',null,null);
     raise exception 'Wrong account accepted';
    exception when raise_exception then
     if sqlerrm='Wrong account accepted' then raise; end if;
    end;
    begin
     perform public.olivia_record_whatsapp_status('WABA1','WRONG','wamid.test1','read','2026-01-01 10:03Z',null,null);
     raise exception 'Wrong phone accepted';
    exception when raise_exception then
     if sqlerrm='Wrong phone accepted' then raise; end if;
    end;
    insert into public.outbound_dispatches(id,message_id,channel,status,external_dispatch_id,whatsapp_waba_id,whatsapp_phone_number_id)
      values('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','whatsapp','sent','wamid.test2','WABA1','PHONE1');
    perform public.olivia_record_whatsapp_status('WABA1','PHONE1','wamid.test2','failed','2026-01-01 11:00Z','131026','Message undeliverable');
    result:=public.olivia_whatsapp_delivery('10000000-0000-0000-0000-000000000002');
    if result->>'status'<>'failed' or result->>'error' not like '%131026%' then raise exception 'Failure lost: %',result; end if;
    perform public.olivia_record_whatsapp_status('WABA1','PHONE1','wamid.test2','read','2026-01-01 11:03Z',null,null);
    perform public.olivia_record_whatsapp_status('WABA1','PHONE1','wamid.test2','failed','2026-01-01 11:04Z','131026','Late failure');
    result:=public.olivia_whatsapp_delivery('10000000-0000-0000-0000-000000000002');
    if result->>'status'<>'read' then raise exception 'Late failure downgraded read: %',result; end if;
    insert into public.outbound_dispatches(id,message_id,channel,status,external_dispatch_id,whatsapp_waba_id,whatsapp_phone_number_id)
      values('00000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000003','whatsapp','sent','wamid.test3','WABA1','PHONE1');
    result:=public.olivia_whatsapp_delivery('10000000-0000-0000-0000-000000000003');
    if result->>'status'<>'sent' or result->>'read_at' is not null then raise exception 'Unconfirmed read inferred: %',result; end if;
    if has_function_privilege('anon','public.olivia_record_whatsapp_status(text,text,text,text,timestamptz,text,text)','execute')
     or has_table_privilege('anon','public.olivia_whatsapp_status_events','select') then raise exception 'Anonymous access granted'; end if;
   end $test$;
  `);
  console.log('PASS: duplicate, out-of-order, early arrival, account scope, failure and access checks');
 } finally { await db.close(); }
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
