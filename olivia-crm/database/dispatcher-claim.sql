CREATE OR REPLACE FUNCTION public.olivia_claim_outbound_v2(p_limit integer DEFAULT 1)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb; alert_cfg jsonb; d public.outbound_dispatches; c public.contacts; conv public.conversations; permission text; internal boolean; outgoing jsonb;claimed_count integer:=0;
begin
 select value into cfg from public.olivia_config where key='bf2026';
 select value into alert_cfg from public.olivia_config where key='handoff_alerts';
 for d in select * from public.outbound_dispatches where channel='whatsapp' and status='pending'
 and payload->>'prompt_version'='bf26-v2' and coalesce(scheduled_for,created_at)<=now()
 and ((payload->>'kind'='human_handoff_alert' and coalesce((alert_cfg->>'enabled')::boolean,false))
 or (payload->>'kind' is distinct from 'human_handoff_alert' and coalesce((cfg->>'whatsapp_outbound_enabled')::boolean,false)))
 and (payload->>'ai_disclosure_dispatch_id' is null or exists(select 1 from public.outbound_dispatches dep where dep.id::text=outbound_dispatches.payload->>'ai_disclosure_dispatch_id' and dep.status in ('sent','delivered') and nullif(dep.external_dispatch_id,'') is not null and dep.error_message is null))
 order by created_at,id limit 100 for update skip locked loop
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
   claimed_count:=claimed_count+1;if claimed_count>=greatest(1,least(p_limit,10)) then return; end if;
   claimed_count:=claimed_count+1;if claimed_count>=greatest(1,least(p_limit,10)) then return; end if;
   continue;
  end if;
  outgoing:=public.olivia_claim_customer_dispatch(d.id);
  if outgoing is not null then return next outgoing;claimed_count:=claimed_count+1;if claimed_count>=greatest(1,least(p_limit,10)) then return; end if; end if;
 end loop;
end;$function$;
revoke all on function public.olivia_claim_outbound_v2(integer) from public,anon,authenticated;
grant execute on function public.olivia_claim_outbound_v2(integer) to service_role;

