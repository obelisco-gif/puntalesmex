create or replace function public.olivia_claim_customer_dispatch(p_id uuid) returns jsonb
language plpgsql set search_path='' as $$
declare d public.outbound_dispatches;c public.contacts;v public.conversations;cfg jsonb;acfg jsonb;permission text;is_notice boolean;in_window boolean;kind text;dtype text;tid text;lang text;components jsonb;
begin
 select value into cfg from public.olivia_config where key='bf2026';
 if not coalesce((cfg->>'whatsapp_outbound_enabled')::boolean,false) then return null; end if;
 select * into d from public.outbound_dispatches where id=p_id and status='pending' and channel='whatsapp' and coalesce(scheduled_for,created_at)<=now() for update skip locked;
 if not found or d.payload->>'kind'='human_handoff_alert' then return null; end if;
 select * into c from public.contacts where id=d.contact_id;
 select * into v from public.conversations where id=d.conversation_id and contact_id=c.id;
 if c.phone is null or v.id is null then return null; end if;
 select status into permission from public.contact_channel_consents where contact_id=c.id and channel='whatsapp';
 if (permission='revoked' and not coalesce((d.payload->>'optout_confirmation')::boolean,false)) or (v.handoff_status in ('human','pending_human') and d.payload->>'sender_role' is distinct from 'human') then
 update public.outbound_dispatches set status='cancelled',error_message='Baja o control humano' where id=d.id;return null; end if;
 is_notice:=coalesce(d.payload->>'kind','')='ai_disclosure';
 if not is_notice and d.payload->>'sender_role' is distinct from 'human' and not c.ai_disclosure_shown then return null; end if;
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
 elsif dtype='freeform' and not in_window then
  update public.outbound_dispatches set status='cancelled',error_message='Ventana de respuesta cerrada' where id=d.id;return null;
 elsif dtype='template' then
  if permission is distinct from 'granted' or not coalesce((cfg->>'whatsapp_template_approved')::boolean,false) or nullif(cfg->>'whatsapp_template_name','') is null then return null; end if;
 end if;
 update public.outbound_dispatches set status='processing',delivery_type=dtype,claimed_at=now(),attempts=attempts+1,last_attempt_at=now() where id=d.id;
 return jsonb_build_object('dispatch_id',d.id,'kind',d.payload->>'kind','phone',c.phone,'delivery_type',dtype,'body',d.payload->>'body','template_name',coalesce(tid,cfg->>'whatsapp_template_name'),'template_language',coalesce(lang,cfg->>'whatsapp_template_language'),'template_components',coalesce(components,cfg->'whatsapp_template_components','[]'),'phone_number_id',cfg->>'whatsapp_phone_number_id');
end;$$;

create or replace function public.olivia_claim_after_ai_disclosure(p_disclosure uuid) returns jsonb
language plpgsql set search_path='' as $$
declare d public.outbound_dispatches;next_id uuid;
begin
 select * into d from public.outbound_dispatches where id=p_disclosure and payload->>'kind'='ai_disclosure' and status in ('sent','delivered') and nullif(external_dispatch_id,'') is not null and error_message is null;
 if not found then return null; end if;
 select id into next_id from public.outbound_dispatches where contact_id=d.contact_id and status='pending' and payload->>'ai_disclosure_dispatch_id'=d.id::text and payload->>'kind' is distinct from 'ai_disclosure' order by case when id::text=d.payload->>'initial_response_id' then 0 else 1 end,created_at,id limit 1 for update skip locked;
 if next_id is null then return null; end if;
 return public.olivia_claim_customer_dispatch(next_id);
end;$$;
revoke all on function public.olivia_claim_customer_dispatch(uuid),public.olivia_claim_after_ai_disclosure(uuid) from public,anon,authenticated;
grant execute on function public.olivia_claim_customer_dispatch(uuid),public.olivia_claim_after_ai_disclosure(uuid) to service_role;
