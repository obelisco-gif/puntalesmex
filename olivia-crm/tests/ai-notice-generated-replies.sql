begin;
do $$
declare c uuid;v uuid;d uuid;r jsonb;
begin
 insert into public.contacts(phone) values('+34999000771') returning id into c;
 insert into public.conversations(contact_id,channel) values(c,'whatsapp') returning id into v;
 insert into public.contact_channel_consents(contact_id,channel,status,source,evidence) values(c,'whatsapp','granted','crm','{}');
 update public.olivia_config set value=value||'{"whatsapp_outbound_enabled":true,"whatsapp_template_name":"welcome_test","whatsapp_template_approved":true,"whatsapp_template_language":"es","whatsapp_phone_number_id":"test-sender"}' where key='bf2026';
 insert into public.outbound_dispatches(contact_id,conversation_id,channel,delivery_type,payload) values(c,v,'whatsapp','template','{"prompt_version":"bf26-v2","welcome_job_id":"test"}') returning id into d;
 if exists(select 1 from public.outbound_dispatches where contact_id=c and payload->>'kind'='ai_disclosure') then raise exception 'Welcome template created AI notice';end if;
 r:=public.olivia_claim_customer_dispatch(d);
 if r is null or r->>'delivery_type'<>'template' then raise exception 'Welcome blocked waiting for AI disclosure';end if;
 perform public.complete_olivia_outbound(d,'fake-welcome-receipt',null);
 if (select ai_disclosure_shown from public.contacts where id=c) then raise exception 'Welcome counted as disclosure';end if;
 insert into public.messages(conversation_id,direction,body) values(v,'inbound','Hola');
 insert into public.outbound_dispatches(contact_id,conversation_id,channel,delivery_type,payload) values(c,v,'whatsapp','freeform','{"prompt_version":"bf26-v2","kind":"bot_reply","body":"Respuesta generada por Olivia"}') returning id into d;
 if not exists(select 1 from public.outbound_dispatches where contact_id=c and payload->>'kind'='ai_disclosure') then raise exception 'First generated response lacks notice';end if;
 if public.olivia_claim_customer_dispatch(d) is not null then raise exception 'Generated response skipped notice';end if;
 r:=public.olivia_dispatcher_claim(d);
 if r->>'kind'<>'ai_disclosure' then raise exception 'First outbound must be AI disclosure';end if;
end;$$;
rollback;
select 'PASS: welcome template sends without AI notice, does not mark notified, and first generated reply requires a separate prior notice.' as result;
