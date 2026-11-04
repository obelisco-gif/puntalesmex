-- Manual replies use the same outbound queue and delivery checks as Olivia.
create or replace function public.olivia_manual_reply(p_conversation uuid,p_body text,p_request uuid,p_expected_updated_at timestamptz,p_actor uuid) returns jsonb
language plpgsql set search_path='' as $$
declare v public.conversations; c public.contacts; d public.outbound_dispatches; mid uuid; cfg jsonb; result jsonb;
begin
 if p_request is null or p_actor is null or nullif(btrim(p_body),'') is null or length(p_body)>2000 then raise exception 'Mensaje no válido'; end if;
 select * into v from public.conversations where id=p_conversation for update;
 if not found then raise exception 'Conversación no encontrada'; end if;
 select value into cfg from public.olivia_config where key='bf2026';
 select * into d from public.outbound_dispatches where idempotency_key='crm-reply:'||p_request;
 if found then
  if d.conversation_id<>v.id or d.payload->>'body'<>btrim(p_body) or d.payload->>'actor_id'<>p_actor::text then raise exception 'Identificador de envío ya utilizado'; end if;
  return jsonb_build_object('dispatch_id',d.id,'message_id',d.message_id,'status',d.status,'duplicate',true,'outbound_enabled',coalesce((cfg->>'whatsapp_outbound_enabled')::boolean,false));
 end if;
 if p_expected_updated_at is distinct from v.updated_at then raise exception 'La conversación ha cambiado'; end if;
 select * into c from public.contacts where id=v.contact_id;
 if v.channel<>'whatsapp' or nullif(c.phone,'') is null then raise exception 'Esta conversación no tiene WhatsApp disponible'; end if;
 if exists(select 1 from public.contact_channel_consents where contact_id=c.id and channel='whatsapp' and status='revoked') then raise exception 'Este contacto ha solicitado la baja de WhatsApp'; end if;
 if not exists(select 1 from public.messages where conversation_id=v.id and direction='inbound' and created_at>now()-interval '23 hours 50 minutes') then raise exception 'La ventana de respuesta de WhatsApp está cerrada. Es necesario que el contacto vuelva a escribir'; end if;
 if v.handoff_status<>'human' then
  result:=public.olivia_save_conversation(v.id,jsonb_build_object('handoff_status','human','expected_updated_at',v.updated_at));
 end if;
 insert into public.messages(conversation_id,direction,body) values(v.id,'outbound',btrim(p_body)) returning id into mid;
 insert into public.outbound_dispatches(contact_id,conversation_id,message_id,channel,delivery_type,payload,idempotency_key,status,scheduled_for)
 values(c.id,v.id,mid,'whatsapp','freeform',jsonb_build_object('prompt_version','bf26-v2','sender_role','human','body',btrim(p_body),'actor_id',p_actor,'origin','crm'),'crm-reply:'||p_request,'pending',now()) returning * into d;
 update public.conversations set updated_at=clock_timestamp(),status='open' where id=v.id;
 insert into public.contact_events(contact_id,event_type,source,metadata,idempotency_key) values(c.id,'manual_reply_queued','crm',jsonb_build_object('conversation_id',v.id,'message_id',mid,'dispatch_id',d.id,'actor_id',p_actor),'crm-reply-event:'||p_request);
 return jsonb_build_object('dispatch_id',d.id,'message_id',mid,'status',d.status,'duplicate',false,'outbound_enabled',coalesce((cfg->>'whatsapp_outbound_enabled')::boolean,false),'in_flight',coalesce((result->>'in_flight')::integer,0));
end;$$;
revoke all on function public.olivia_manual_reply(uuid,text,uuid,timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.olivia_manual_reply(uuid,text,uuid,timestamptz,uuid) to service_role;

create or replace function public.olivia_claim_outbound_v2(p_limit integer default 1)
returns setof jsonb language plpgsql security definer set search_path='' as $f$
declare cfg jsonb; d public.outbound_dispatches; c public.contacts; conv public.conversations; permission text;
begin
 select value into cfg from public.olivia_config where key='bf2026';
 if not coalesce((cfg->>'whatsapp_outbound_enabled')::boolean,false) then return; end if;
 for d in select * from public.outbound_dispatches where channel='whatsapp' and status='pending'
 and payload->>'prompt_version'='bf26-v2' and coalesce(scheduled_for,created_at)<=now()
 order by created_at limit greatest(1,least(p_limit,10)) for update skip locked loop
  select * into c from public.contacts where id=d.contact_id;
  select * into conv from public.conversations where id=d.conversation_id;
  select status into permission from public.contact_channel_consents where contact_id=c.id and channel='whatsapp';
  if (permission='revoked' and not coalesce((d.payload->>'optout_confirmation')::boolean,false))
    or (conv.handoff_status in ('human','pending_human') and d.payload->>'sender_role' is distinct from 'human') then
    update public.outbound_dispatches set status='cancelled',error_message='Baja o control humano' where id=d.id; continue;
  end if;
  if d.delivery_type='freeform' and not exists(select 1 from public.messages where conversation_id=d.conversation_id and direction='inbound' and created_at>now()-interval '23 hours 50 minutes') then
    update public.outbound_dispatches set status='cancelled',error_message='Ventana de respuesta cerrada' where id=d.id; continue;
  end if;
  if d.delivery_type='template' and (permission is distinct from 'granted' or not coalesce((cfg->>'whatsapp_template_approved')::boolean,false) or nullif(cfg->>'whatsapp_template_name','') is null) then continue; end if;
  if c.phone is null then continue; end if;
  update public.outbound_dispatches set status='processing',claimed_at=now(),attempts=attempts+1,last_attempt_at=now() where id=d.id;
  return next jsonb_build_object('dispatch_id',d.id,'phone',c.phone,'delivery_type',d.delivery_type,'body',d.payload->>'body','template_name',cfg->>'whatsapp_template_name','template_language',cfg->>'whatsapp_template_language','template_components',coalesce(cfg->'whatsapp_template_components','[]'),'phone_number_id',cfg->>'whatsapp_phone_number_id');
 end loop;
end;$f$;


revoke all on function public.olivia_claim_outbound_v2(integer) from public,anon,authenticated;
grant execute on function public.olivia_claim_outbound_v2(integer) to service_role;
