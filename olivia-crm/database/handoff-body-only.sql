CREATE OR REPLACE FUNCTION public.olivia_prepare_handoff_notifications()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare cfg jsonb;h public.olivia_handoffs;did uuid;params jsonb;components jsonb;link text;prepared integer:=0;
begin
 select value into cfg from public.olivia_config where key='handoff_alerts';
 if not coalesce((cfg->>'enabled')::boolean,false) or not coalesce((cfg->>'recipient_confirmed')::boolean,false)
 or not coalesce((cfg->>'template_approved')::boolean,false) or coalesce(cfg->>'recipient_phone','')!~'^\+[1-9][0-9]{7,14}$'
 or length(coalesce(cfg->>'template_name','')) not between 2 and 512 or coalesce(cfg->>'template_name','')!~'^[a-z][a-z0-9_]+$' then return jsonb_build_object('prepared',0,'reason','Número o plantilla pendientes de configurar y autorizar'); end if;
 for h in select * from public.olivia_handoffs where conversation_id is not null and status in ('requested','active') and notification_requested and notification_dispatch_id is null order by created_at limit 25 for update skip locked loop
  link:='https://olivia-crm-weld.vercel.app/?tab=conversaciones&conversation='||h.conversation_id;
  params:=jsonb_build_array(
   left(regexp_replace(coalesce(h.contact_snapshot->>'name','Sin nombre confirmado'),'\s+',' ','g'),60),
   left(coalesce(h.contact_snapshot->>'phone','Sin teléfono'),32),
   left(regexp_replace(h.reason,'\s+',' ','g'),240),
   left(regexp_replace(h.summary,'\s+',' ','g'),360),link,
   case when h.source='crm' then 'Intervención manual' else 'Derivación de Olivia' end);
  select jsonb_build_array(jsonb_build_object('type','body','parameters',(select jsonb_agg(jsonb_build_object('type','text','text',x)) from jsonb_array_elements_text(params)x))) into components;
  -- Internal recipient: deliberately no contact/conversation/message FK on this dispatch.
  insert into public.outbound_dispatches(channel,delivery_type,payload,idempotency_key,status,scheduled_for)
  values('whatsapp','template',jsonb_build_object('prompt_version','bf26-v2','kind','human_handoff_alert','handoff_id',h.id,'recipient_phone',cfg->>'recipient_phone','template_name',cfg->>'template_name','template_language',coalesce(cfg->>'template_language','es'),'template_components',components),'handoff-alert:'||h.id,'pending',now())
  on conflict(idempotency_key) where idempotency_key is not null do nothing returning id into did;
  if did is null then select id into did from public.outbound_dispatches where idempotency_key='handoff-alert:'||h.id; end if;
  update public.olivia_handoffs set notification_dispatch_id=did,updated_at=clock_timestamp() where id=h.id;
  insert into public.olivia_handoff_events(handoff_id,event_type,actor,metadata) values(h.id,'notification_queued','outbound',jsonb_build_object('dispatch_id',did));
  prepared:=prepared+1;
 end loop;
 return jsonb_build_object('prepared',prepared);
end;$function$;
