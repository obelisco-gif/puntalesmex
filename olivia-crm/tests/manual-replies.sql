begin;
do $$
declare c uuid; v uuid; stamp timestamptz; req uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); r jsonb; again jsonb; claimed jsonb; n integer;
begin
 insert into public.contacts(phone,source) values('+34999000088','crm') returning id into c;
 insert into public.conversations(contact_id,channel) values(c,'whatsapp') returning id,updated_at into v,stamp;
 insert into public.messages(conversation_id,direction,body) values(v,'inbound','Consulta de prueba');
 insert into public.outbound_dispatches(contact_id,conversation_id,channel,payload) values(c,v,'whatsapp','{"prompt_version":"bf26-v2","body":"AI vieja"}');
 r:=public.olivia_manual_reply(v,'Respuesta del equipo',req,stamp,actor);
 if r->>'status'<>'pending' or (r->>'outbound_enabled')::boolean then raise exception 'Must queue with outbound paused'; end if;
 if (select handoff_status from public.conversations where id=v)<>'human' then raise exception 'Must take control'; end if;
 if (select status from public.outbound_dispatches where conversation_id=v and payload->>'body'='AI vieja')<>'cancelled' then raise exception 'Must cancel stale AI reply'; end if;
 again:=public.olivia_manual_reply(v,'Respuesta del equipo',req,stamp,actor);
 if not (again->>'duplicate')::boolean or again->>'dispatch_id'<>r->>'dispatch_id' then raise exception 'Retry duplicated message'; end if;
 select count(*) into n from public.messages where conversation_id=v and direction='outbound' and body='Respuesta del equipo';
 if n<>1 then raise exception 'History duplicated'; end if;
 select count(*) into n from public.olivia_claim_outbound_v2(1);
 if n<>0 then raise exception 'Master pause bypassed'; end if;
 select updated_at into stamp from public.conversations where id=v;
 perform public.olivia_save_conversation(v,jsonb_build_object('handoff_status','bot','expected_updated_at',stamp));
 if (select status from public.outbound_dispatches where id=(r->>'dispatch_id')::uuid)<>'pending' then raise exception 'Returning control cancelled human message'; end if;
 select updated_at into stamp from public.conversations where id=v;
 perform public.olivia_save_conversation(v,jsonb_build_object('handoff_status','human','expected_updated_at',stamp));
 update public.olivia_config set value=jsonb_set(value,'{whatsapp_outbound_enabled}','true') where key='bf2026';
 select x into claimed from public.olivia_claim_outbound_v2(1)x;
 if claimed->>'dispatch_id'<>r->>'dispatch_id' or claimed->>'body'<>'Respuesta del equipo' then raise exception 'Sender rejected manual message during human control'; end if;
 insert into public.outbound_dispatches(contact_id,conversation_id,channel,delivery_type,payload) values(c,v,'whatsapp','freeform','{"prompt_version":"bf26-v2","body":"AI no autorizada"}');
 select count(*) into n from public.olivia_claim_outbound_v2(1);
 if n<>0 then raise exception 'AI sent during human control'; end if;
 select updated_at into stamp from public.conversations where id=v;
 insert into public.contact_channel_consents(contact_id,channel,status,source) values(c,'whatsapp','revoked','crm');
 begin
 perform public.olivia_manual_reply(v,'No debe enviarse',gen_random_uuid(),stamp,actor);
 raise exception 'Revoked contact accepted';
 exception when others then if sqlerrm not like '%solicitado la baja%' then raise; end if; end;
 delete from public.contact_channel_consents where contact_id=c;
 update public.messages set created_at=now()-interval '25 hours' where conversation_id=v and direction='inbound';
 begin
 perform public.olivia_manual_reply(v,'Fuera de ventana',gen_random_uuid(),stamp,actor);
 raise exception 'Closed window accepted';
 exception when others then if sqlerrm not like '%ventana de respuesta%' then raise; end if; end;
 if has_function_privilege('anon','public.olivia_manual_reply(uuid,text,uuid,timestamptz,uuid)','execute') then raise exception 'Manual reply publicly exposed'; end if;
end;$$;
select 'PASS: atomic manual queue + history + takeover, idempotent retry, master pause, return preserves manual messages, sender permits humans and blocks AI, STOP and window checks.' as result;
rollback;
