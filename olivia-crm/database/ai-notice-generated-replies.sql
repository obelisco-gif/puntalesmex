create or replace function public.olivia_dispatch_needs_ai_notice(p_dispatch jsonb) returns boolean language sql immutable set search_path='' as $$
select coalesce(p_dispatch->>'channel'='whatsapp'
 and coalesce(p_dispatch->>'delivery_type','freeform')<>'template'
 and p_dispatch#>>'{payload,prompt_version}'='bf26-v2'
 and p_dispatch#>>'{payload,sender_role}' is distinct from 'human'
 and coalesce(p_dispatch#>>'{payload,kind}','') not in ('ai_disclosure','human_handoff_alert')
 and p_dispatch#>>'{payload,welcome_job_id}' is null
 and not coalesce((p_dispatch#>>'{payload,optout_confirmation}')::boolean,false),false);
$$;
revoke all on function public.olivia_dispatch_needs_ai_notice(jsonb) from public,anon,authenticated;
grant execute on function public.olivia_dispatch_needs_ai_notice(jsonb) to service_role;
CREATE OR REPLACE FUNCTION public.olivia_disclosure_before_outbound()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare did uuid;
begin
 if new.contact_id is not null and new.conversation_id is not null and public.olivia_dispatch_needs_ai_notice(to_jsonb(new)) then
  did:=public.olivia_ensure_ai_disclosure(new.contact_id,new.conversation_id,new.payload,new.created_at,new.message_id,new.id);
  if did is not null then new.payload:=new.payload||jsonb_build_object('ai_disclosure_dispatch_id',did); end if;
 end if;
 return new;
end;$function$;
revoke all on function public.olivia_disclosure_before_outbound() from public,anon,authenticated;
grant execute on function public.olivia_disclosure_before_outbound() to service_role;
CREATE OR REPLACE FUNCTION public.olivia_claim_customer_dispatch(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare d public.outbound_dispatches;c public.contacts;v public.conversations;cfg jsonb;acfg jsonb;permission text;is_notice boolean;in_window boolean;kind text;dtype text;tid text;lang text;components jsonb;
begin
 select value into cfg from public.olivia_config where key='bf2026';
 if not coalesce((cfg->>'whatsapp_outbound_enabled')::boolean,false) then return null; end if;
 select * into d from public.outbound_dispatches where id=p_id and status='pending' and channel='whatsapp' and coalesce(scheduled_for,created_at)<=now() for update skip locked;
 if not found or d.payload->>'kind'='human_handoff_alert' then return null; end if;
 select * into c from public.contacts where id=d.contact_id;
 select * into v from public.conversations where id=d.conversation_id and contact_id=c.id;
 if c.phone is null or v.id is null or nullif(cfg->>'whatsapp_phone_number_id','') is null then return null; end if;
 if d.payload->>'ai_disclosure_dispatch_id' is not null and not exists(select 1 from public.outbound_dispatches dep where dep.id::text=d.payload->>'ai_disclosure_dispatch_id' and dep.status in ('sent','delivered') and nullif(dep.external_dispatch_id,'') is not null and dep.error_message is null) then return null; end if;
 select status into permission from public.contact_channel_consents where contact_id=c.id and channel='whatsapp';
 if (permission='revoked' and not coalesce((d.payload->>'optout_confirmation')::boolean,false)) or (v.handoff_status in ('human','pending_human') and d.payload->>'sender_role' is distinct from 'human' and not coalesce((v.handoff_status='pending_human' and (d.payload->>'kind'='handoff_acknowledgement' or (d.payload->>'kind'='ai_disclosure' and exists(select 1 from public.outbound_dispatches ack where ack.id::text=d.payload->>'initial_response_id' and ack.payload->>'kind'='handoff_acknowledgement' and ack.status='pending')))),false)) then
 update public.outbound_dispatches set status='cancelled',error_message='Baja o control humano' where id=d.id;return null; end if;
 is_notice:=coalesce(d.payload->>'kind','')='ai_disclosure';
 if public.olivia_dispatch_needs_ai_notice(to_jsonb(d)) and not c.ai_disclosure_shown then return null; end if;
 select exists(select 1 from public.messages where conversation_id=v.id and direction='inbound' and created_at>now()-interval '23 hours 50 minutes') into in_window;
 dtype:=d.delivery_type;
 if is_notice then
  if c.ai_disclosure_shown then update public.outbound_dispatches set status='cancelled',error_message='Aviso IA ya confirmado' where id=d.id;return null; end if;
  if in_window then dtype:='freeform';
  else
   select value into acfg from public.olivia_config where key='ai_disclosure';
   if permission is distinct from 'granted' or not coalesce((acfg->>'template_approved')::boolean,false) or nullif(acfg->>'template_name','') is null then return null; end if;
   dtype:='template';tid:=acfg->>'template_name';lang:=coalesce(acfg->>'template_language','es');components:='[]';
  end if;
 elsif dtype in ('freeform','lead_magnet','checkout_link') and not in_window then
  update public.outbound_dispatches set status='cancelled',error_message='Ventana de respuesta cerrada' where id=d.id;return null;
 elsif dtype='template' then
  tid:=coalesce(nullif(d.payload->>'template_name',''),cfg->>'whatsapp_template_name');
  if permission is distinct from 'granted' or tid is null then return null; end if;
  if not ((tid=cfg->>'whatsapp_template_name' and coalesce((cfg->>'whatsapp_template_approved')::boolean,false)) or exists(select 1 from public.olivia_config t where t.key='outbound_templates' and coalesce((t.value#>>array[tid,'approved'])::boolean,false))) then return null; end if;
  lang:=coalesce(nullif(d.payload->>'template_language',''),cfg->>'whatsapp_template_language','es');components:=coalesce(d.payload->'template_components',cfg->'whatsapp_template_components','[]');
 end if;
 update public.outbound_dispatches set status='processing',delivery_type=dtype,claimed_at=now(),attempts=attempts+1,last_attempt_at=now() where id=d.id;
 return jsonb_build_object('dispatch_id',d.id,'kind',d.payload->>'kind','phone',c.phone,'delivery_type',dtype,'body',coalesce(d.payload->>'body',(select body from public.messages where id=d.message_id)),'image_url',d.payload->>'image_url','caption',d.payload->>'caption','sender_role',d.payload->>'sender_role','attempts',d.attempts+1,'template_name',coalesce(tid,cfg->>'whatsapp_template_name'),'template_language',coalesce(lang,cfg->>'whatsapp_template_language'),'template_components',coalesce(components,cfg->'whatsapp_template_components','[]'),'phone_number_id',cfg->>'whatsapp_phone_number_id');
end;$function$;
revoke all on function public.olivia_claim_customer_dispatch(uuid) from public,anon,authenticated;
grant execute on function public.olivia_claim_customer_dispatch(uuid) to service_role;
