begin;
do $$
declare c uuid;v uuid;parent uuid;notice uuid;r jsonb;next_item jsonb;second uuid;mid uuid;n integer;stamp timestamptz;
begin
 insert into public.contacts(phone,source) values('+34999000066','crm') returning id into c;
 insert into public.conversations(contact_id,channel) values(c,'whatsapp') returning id into v;
 insert into public.messages(conversation_id,direction,body) values(v,'inbound','Hola');
 insert into public.messages(conversation_id,direction,body) values(v,'outbound','Hola, ¿en qué puedo ayudarte?') returning id into mid;
 insert into public.outbound_dispatches(contact_id,conversation_id,message_id,channel,delivery_type,payload) values(c,v,mid,'whatsapp','freeform','{"prompt_version":"bf26-v2","body":"Hola, ¿en qué puedo ayudarte?"}') returning id into parent;
 select ai_disclosure_dispatch_id into notice from public.contacts where id=c;
 if notice is null or (select ai_disclosure_shown from public.contacts where id=c) then raise exception 'Notice not queued or marked shown prematurely'; end if;
 if (select body from public.messages where id=(select message_id from public.outbound_dispatches where id=notice))<>'Nota: este chat puede contar con apoyo de ia' then raise exception 'Disclosure text differs'; end if;
 insert into public.outbound_dispatches(contact_id,conversation_id,channel,delivery_type,payload) values(c,v,'whatsapp','freeform','{"prompt_version":"bf26-v2","body":"Segundo mensaje"}') returning id into second;
 if (select count(*) from public.outbound_dispatches where contact_id=c and payload->>'kind'='ai_disclosure')<>1 then raise exception 'Duplicate notices'; end if;
 update public.olivia_config set value=jsonb_set(value,'{whatsapp_outbound_enabled}','true') where key='bf2026';
 if public.olivia_claim_customer_dispatch(parent) is not null then raise exception 'Reply sent before disclosure'; end if;
 select x into r from public.olivia_claim_outbound_v2(1)x;
 if r->>'dispatch_id'<>notice::text or r->>'kind'<>'ai_disclosure' then raise exception 'Notice not first'; end if;
 perform public.complete_olivia_outbound(notice,null,null);
 if (select ai_disclosure_shown from public.contacts where id=c) or public.olivia_claim_after_ai_disclosure(notice) is not null then raise exception 'Unknown send marked informed or released reply'; end if;
 -- Explicitly simulate an operator-confirmed retry; no automatic retry of uncertainty.
 update public.outbound_dispatches set status='processing' where id=notice;
 perform public.complete_olivia_outbound(notice,'wamid.fake-disclosure',null);
 if not (select ai_disclosure_shown from public.contacts where id=c) or (select ai_disclosure_shown_at from public.contacts where id=c) is null then raise exception 'Confirmed disclosure not recorded'; end if;
 next_item:=public.olivia_claim_after_ai_disclosure(notice);
 if next_item->>'dispatch_id'<>parent::text then raise exception 'Immediate follow-up not the original reply'; end if;
 if public.olivia_claim_after_ai_disclosure(notice)->>'dispatch_id'=parent::text then raise exception 'Parent claimed twice'; end if;
 perform public.complete_olivia_outbound(parent,'wamid.fake-response',null);
 insert into public.outbound_dispatches(contact_id,conversation_id,channel,delivery_type,payload) values(c,v,'whatsapp','freeform','{"prompt_version":"bf26-v2","body":"Otro turno"}');
 if (select count(*) from public.outbound_dispatches where contact_id=c and payload->>'kind'='ai_disclosure')<>1 then raise exception 'Notice repeated after confirmation'; end if;
 if (select count(*) from public.contact_events where contact_id=c and event_type='ai_disclosure_sent')<>1 then raise exception 'Missing or duplicate receipt audit'; end if;
 -- Human replies and internal handoff alerts are not first AI messages.
 insert into public.contacts(phone,source) values('+34999000065','crm') returning id into c;
 insert into public.conversations(contact_id,channel,handoff_status) values(c,'whatsapp','human') returning id into v;
 insert into public.outbound_dispatches(contact_id,conversation_id,channel,delivery_type,payload) values(c,v,'whatsapp','freeform','{"prompt_version":"bf26-v2","sender_role":"human","body":"Soy del equipo"}');
 if (select ai_disclosure_dispatch_id from public.contacts where id=c) is not null then raise exception 'Human message got AI notice'; end if;
 -- Outside the response window a separate approved disclosure template is required.
 insert into public.contacts(phone,source) values('+34999000064','crm') returning id into c;
 insert into public.conversations(contact_id,channel) values(c,'whatsapp') returning id into v;
 insert into public.contact_channel_consents(contact_id,channel,status,source) values(c,'whatsapp','granted','crm');
 insert into public.outbound_dispatches(contact_id,conversation_id,channel,delivery_type,payload) values(c,v,'whatsapp','template','{"prompt_version":"bf26-v2"}') returning id into parent;
 select ai_disclosure_dispatch_id into notice from public.contacts where id=c;
 if public.olivia_claim_customer_dispatch(notice) is not null then raise exception 'Unapproved template sent outside window'; end if;
 update public.olivia_config set value=jsonb_set(value,'{template_approved}','true') where key='ai_disclosure';
 r:=public.olivia_claim_customer_dispatch(notice);
 if r->>'delivery_type'<>'template' or r->>'template_name'<>'olivia_aviso_ia' then raise exception 'Disclosure template mapping incorrect'; end if;
 if has_function_privilege('anon','public.olivia_claim_after_ai_disclosure(uuid)','execute') then raise exception 'Disclosure sender publicly exposed'; end if;
end;$$;
select 'PASS: exact first notice, once per lead, ordering, provider-confirmed receipt, failure blocking, immediate separate reply, human/internal exclusion and outside-window template guard.' as result;
rollback;
