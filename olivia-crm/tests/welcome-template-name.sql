begin;
do $$
declare a uuid;b uuid;r jsonb;payload_a jsonb;payload_b jsonb;
begin
 update public.olivia_config set value=value||'{"whatsapp_template_name":"bvea26","whatsapp_template_language":"es","whatsapp_template_approved":true}' where key='bf2026';
 insert into public.contacts(phone,first_name,manual_tags) values('+34999000781','Ana Pérez',array['bf2026_early_access']) returning id into a;
 insert into public.contacts(phone,first_name,manual_tags) values('+34999000782','Luis García',array['bf2026_early_access']) returning id into b;
 insert into public.contact_channel_consents(contact_id,channel,status,source,evidence) values(a,'whatsapp','granted','crm','{}'),(b,'whatsapp','granted','crm','{}');
 perform public.olivia_prepare_welcome();
 select payload into payload_a from public.outbound_dispatches where contact_id=a and payload->>'kind'='early_access_welcome';
 select payload into payload_b from public.outbound_dispatches where contact_id=b and payload->>'kind'='early_access_welcome';
 if payload_a->>'template_name' is distinct from 'bvea26' or payload_a->>'template_language' is distinct from 'es' then raise exception 'Wrong template or language';end if;
 if payload_a#>>'{template_components,0,parameters,0,text}' is distinct from 'Ana Pérez' or payload_b#>>'{template_components,0,parameters,0,text}' is distinct from 'Luis García' then raise exception 'Names mixed or missing';end if;
 if jsonb_array_length(payload_a#>'{template_components,0,parameters}')<>1 then raise exception 'Template must have exactly one parameter';end if;
 if exists(select 1 from public.outbound_dispatches where contact_id in (a,b) and payload->>'kind'='ai_disclosure') then raise exception 'Welcome triggered AI notice';end if;
 perform public.olivia_prepare_welcome();
 if (select count(*) from public.outbound_dispatches where contact_id in (a,b))<>2 then raise exception 'Welcome duplicated';end if;
end;$$;
rollback;
select 'PASS: bvea26/es, exactly one lead-specific name, no crossed names, no AI notice and no duplicate welcome.' as result;
