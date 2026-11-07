-- One dispatcher; internal alerts have an independently gated recipient/template.
create or replace function public.olivia_claim_outbound_v2(p_limit integer default 1)
returns setof jsonb language plpgsql security definer set search_path='' as $$
declare cfg jsonb; alert_cfg jsonb; d public.outbound_dispatches; c public.contacts; conv public.conversations; permission text; internal boolean;
begin
 select value into cfg from public.olivia_config where key='bf2026';
 select value into alert_cfg from public.olivia_config where key='handoff_alerts';
 for d in select * from public.outbound_dispatches where channel='whatsapp' and status='pending'
 and payload->>'prompt_version'='bf26-v2' and coalesce(scheduled_for,created_at)<=now()
 and ((payload->>'kind'='human_handoff_alert' and coalesce((alert_cfg->>'enabled')::boolean,false))
 or (payload->>'kind' is distinct from 'human_handoff_alert' and coalesce((cfg->>'whatsapp_outbound_enabled')::boolean,false)))
 order by created_at,id limit greatest(1,least(p_limit,10)) for update skip locked loop
  internal:=d.payload->>'kind'='human_handoff_alert';
  if coalesce(internal,false) then
   if not coalesce((alert_cfg->>'recipient_confirmed')::boolean,false) or not coalesce((alert_cfg->>'template_approved')::boolean,false)
   or coalesce(alert_cfg->>'recipient_phone','')!~'^\+[1-9][0-9]{7,14}$' then continue; end if;
   if d.contact_id is not null or d.conversation_id is not null or d.message_id is not null or d.delivery_type<>'template'
   or d.payload->>'recipient_phone' is distinct from alert_cfg->>'recipient_phone'
   or d.payload->>'template_name' is distinct from alert_cfg->>'template_name'
   or d.payload->>'template_language' is distinct from coalesce(alert_cfg->>'template_language','es')
   or not exists(select 1 from public.olivia_handoffs h where h.id::text=d.payload->>'handoff_id' and h.notification_dispatch_id=d.id and h.status in ('requested','active')) then
    update public.outbound_dispatches set status='cancelled',error_message='Caso cerrado o configuración del aviso modificada' where id=d.id;continue;
   end if;
   if nullif(cfg->>'whatsapp_phone_number_id','') is null then continue; end if;
   update public.outbound_dispatches set status='processing',claimed_at=now(),attempts=attempts+1,last_attempt_at=now() where id=d.id;
   return next jsonb_build_object('dispatch_id',d.id,'kind','human_handoff_alert','phone',d.payload->>'recipient_phone','delivery_type','template','template_name',d.payload->>'template_name','template_language',d.payload->>'template_language','template_components',d.payload->'template_components','phone_number_id',cfg->>'whatsapp_phone_number_id');
   continue;
  end if;
  select * into c from public.contacts where id=d.contact_id;
  select * into conv from public.conversations where id=d.conversation_id;
  select status into permission from public.contact_channel_consents where contact_id=c.id and channel='whatsapp';
  if (permission='revoked' and not coalesce((d.payload->>'optout_confirmation')::boolean,false))
    or (conv.handoff_status in ('human','pending_human') and d.payload->>'sender_role' is distinct from 'human') then
    update public.outbound_dispatches set status='cancelled',error_message='Baja o control humano' where id=d.id;continue;
  end if;
  if d.delivery_type='freeform' and not exists(select 1 from public.messages where conversation_id=d.conversation_id and direction='inbound' and created_at>now()-interval '23 hours 50 minutes') then
    update public.outbound_dispatches set status='cancelled',error_message='Ventana de respuesta cerrada' where id=d.id;continue;
  end if;
  if d.delivery_type='template' and (permission is distinct from 'granted' or not coalesce((cfg->>'whatsapp_template_approved')::boolean,false) or nullif(cfg->>'whatsapp_template_name','') is null) then continue; end if;
  if c.phone is null then continue; end if;
  update public.outbound_dispatches set status='processing',claimed_at=now(),attempts=attempts+1,last_attempt_at=now() where id=d.id;
  return next jsonb_build_object('dispatch_id',d.id,'phone',c.phone,'delivery_type',d.delivery_type,'body',d.payload->>'body','template_name',cfg->>'whatsapp_template_name','template_language',cfg->>'whatsapp_template_language','template_components',coalesce(cfg->'whatsapp_template_components','[]'),'phone_number_id',cfg->>'whatsapp_phone_number_id');
 end loop;
end;$$;
revoke all on function public.olivia_claim_outbound_v2(integer) from public,anon,authenticated;
grant execute on function public.olivia_claim_outbound_v2(integer) to service_role;
