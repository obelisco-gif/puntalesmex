begin;
do $t$
declare c uuid;v uuid;did uuid;mid uuid;p text;r jsonb;
begin
 insert into public.contacts(email,phone,first_name) values('qa-template@example.invalid','+34999000235','Prueba') returning id into c;
 insert into public.conversations(contact_id,channel) values(c,'whatsapp') returning id into v;
 insert into public.outbound_dispatches(contact_id,conversation_id,channel,delivery_type,status,payload)
 values(c,v,'whatsapp','template','pending',jsonb_build_object('template_name','bvea26','template_components',jsonb_build_array(jsonb_build_object('type','body','parameters',jsonb_build_array(jsonb_build_object('type','text','text','Prueba')))))) returning id into did;
 if exists(select 1 from public.messages where conversation_id=v) then raise exception 'Unsent template visible as sent';end if;
 update public.outbound_dispatches set status='sent',sent_at=now(),external_dispatch_id='test-wamid' where id=did;
 select message_id into mid from public.outbound_dispatches where id=did;
 if mid is null or not exists(select 1 from public.messages where id=mid and body like '%bvea26%' and body like '%no disponible%' and external_message_id='test-wamid') then raise exception 'Missing honest fallback history';end if;
 update public.outbound_dispatches set status='sent' where id=did;
 if (select count(*) from public.messages where conversation_id=v)<>1 then raise exception 'Duplicate template';end if;
 p:=encode(convert_to(jsonb_build_object('contact_id',c,'conversation_id',v)::text,'utf8'),'base64');r:=public.olivia_orchestrator_context_b64(p);
 if not exists(select 1 from jsonb_array_elements(r->'history')x where x->>'body' like '%bvea26%') then raise exception 'Agent cannot see template';end if;
 update public.olivia_config set value=value||jsonb_build_object('whatsapp_template_name','bvea26','whatsapp_template_body','Hola {{1}}, bienvenida') where key='bf2026';
 insert into public.outbound_dispatches(contact_id,conversation_id,channel,delivery_type,status,payload)
 values(c,v,'whatsapp','template','sent',jsonb_build_object('template_name','bvea26','template_components',jsonb_build_array(jsonb_build_object('type','body','parameters',jsonb_build_array(jsonb_build_object('type','text','text','Prueba')))))) returning message_id into mid;
 if not exists(select 1 from public.messages where conversation_id=v and body='Hola Prueba, bienvenida') then raise exception 'Exact approved text not rendered';end if;
end;$t$;rollback;
select 'PASS: sent templates appear once in shared history, unsent excluded, exact text or honest fallback' as result;
