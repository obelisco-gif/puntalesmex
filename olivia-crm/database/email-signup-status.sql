create or replace function public.olivia_email_signup_status(p_contact uuid) returns jsonb language plpgsql set search_path='' as $$
declare c public.contacts;j public.olivia_integration_jobs;permission text;state text;reason text;
begin
 select * into c from public.contacts where id=p_contact;
 if not found then return '{}'::jsonb;end if;
 select status into permission from public.contact_channel_consents where contact_id=c.id and channel='email';
 select * into j from public.olivia_integration_jobs where contact_id=c.id and kind='klaviyo_early_access' order by created_at desc,id desc limit 1;
 state:=case when c.email is null then 'no_email' when permission is distinct from 'granted' then 'consent_missing'
 when j.status='completed' and j.payload->>'membership_confirmed'='true' then 'confirmed'
 when j.status='blocked' then 'blocked' when j.status='failed' then 'failed'
 when j.status in ('pending','processing','waiting_consent') then 'pending' else 'not_requested' end;
 reason:=case when state in ('blocked','failed') then j.last_error else null end;
 return jsonb_build_object('email',c.email,'status',state,'membership_confirmed',state='confirmed','consent_recorded',permission='granted',
 'reason_code',j.payload->>'block_reason','reason',reason,'last_checked_at',j.updated_at);
end;$$;
revoke all on function public.olivia_email_signup_status(uuid) from public,anon,authenticated;
grant execute on function public.olivia_email_signup_status(uuid) to service_role;
CREATE OR REPLACE FUNCTION public.olivia_context_v2_b64(p_payload_b64 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb; result jsonb;
begin
 select jsonb_build_object(
 'contact_id',c.id,'conversation_id',v.id,'batch_text',p->>'batch_text','batch_ids',coalesce(p->'batch_ids','[]'::jsonb),
 'contact',jsonb_build_object('first_name',c.first_name,'email',c.email,'phone',c.phone,'stage',c.stage,'source',c.source,'tags',c.manual_tags,'preferences',c.preferences,'attributes',public.olivia_get_attributes(c.id)),
 'email_signup',public.olivia_email_signup_status(c.id),
 'purchase_history',public.olivia_purchase_history(c.id),
 'attributes',public.olivia_get_attributes(c.id),
 'attribute_records',coalesce((select jsonb_agg(to_jsonb(a) order by attribute_key) from public.lead_attributes a where contact_id=c.id and status='confirmed'),'[]'),
 'tool_results',coalesce((select jsonb_agg(metadata) from public.contact_events where contact_id=c.id and event_type='agent_tool' and metadata->'batch_ids' @> coalesce(p->'batch_ids','[]') and metadata->'batch_ids' <@ coalesce(p->'batch_ids','[]')),'[]'),
 'commercial_profile',public.olivia_commercial_profile(c.id),
 'commercial_entries',coalesce((select jsonb_agg(to_jsonb(e) order by e.updated_at desc) from (select * from public.contact_commercial_entries where contact_id=c.id order by updated_at desc limit 50)e),'[]'::jsonb),
 'score',public.olivia_contact_score(c.id),
 'lead_state',coalesce(c.preferences->'olivia','{}'::jsonb)||coalesce((select to_jsonb(ls)-'contact_id' from public.lead_states ls where ls.contact_id=c.id),'{}'),
 'conversation',jsonb_build_object('status',v.status,'handoff_status',v.handoff_status),
 'channel_consents',coalesce((select jsonb_object_agg(channel,jsonb_build_object('status',status,'recorded_at',recorded_at)) from public.contact_channel_consents where contact_id=c.id),'{}'::jsonb),
 'campaign',(select value from public.olivia_config where key='bf2026'),
 'early_access_registered','bf2026_early_access'=any(c.manual_tags),
 'history',coalesce((select jsonb_agg(to_jsonb(h) order by created_at) from (select direction,body,created_at from public.messages where conversation_id=v.id order by created_at desc limit 20)h),'[]'::jsonb),
 'document_index',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'title',d.title,'packages',d.routing_packages,'product_ids',public.olivia_document_product_ids(d.id,d.catalog_product_id))) from public.product_documents d where d.approval_status='approved' and not d.routing_packages && array['internal_ops']),'[]'::jsonb),
 'products',coalesce((select jsonb_agg(public.olivia_catalog_product_context(id,false)) from public.catalog_products where status='publish'),'[]'::jsonb),
 'now',now()) into result
 from public.contacts c join public.conversations v on v.contact_id=c.id
 where c.id=(p->>'contact_id')::uuid and v.id=(p->>'conversation_id')::uuid;
 return coalesce(result,'{}'::jsonb);
end;$function$;
revoke all on function public.olivia_context_v2_b64(text) from public,anon,authenticated;
grant execute on function public.olivia_context_v2_b64(text) to service_role;
