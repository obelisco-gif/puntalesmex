CREATE OR REPLACE FUNCTION public.olivia_enqueue_tag_jobs()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if 'bf2026_early_access'=any(new.manual_tags) then
   insert into public.olivia_integration_jobs(contact_id,kind,idempotency_key)
   values(new.id,'klaviyo_early_access','bf2026:'||new.id||':klaviyo')
   on conflict(idempotency_key) do update set
    status=case when public.olivia_integration_jobs.status='waiting_consent' then 'pending' else public.olivia_integration_jobs.status end,
    updated_at=now();
   if new.phone is not null and coalesce(new.preferences#>>'{early_access,source}','')<>'conversation' then
    insert into public.olivia_integration_jobs(contact_id,kind,idempotency_key) values(new.id,'whatsapp_welcome','bf2026:'||new.id||':whatsapp')
    on conflict(idempotency_key) do nothing;
   else
    update public.olivia_integration_jobs set status='cancelled',last_error='Bienvenida conversacional o sin móvil',updated_at=now()
    where contact_id=new.id and kind='whatsapp_welcome' and status in ('pending','waiting_consent');
    update public.outbound_dispatches set status='cancelled',error_message='Bienvenida conversacional o sin móvil'
    where contact_id=new.id and delivery_type='template' and status='pending' and payload ? 'welcome_job_id';
   end if;
 else
   update public.olivia_integration_jobs set status='cancelled',updated_at=now()
   where contact_id=new.id and campaign='bf2026_early_access' and status in ('pending','waiting_consent');
 end if;
 return new;
end;$function$;

CREATE OR REPLACE FUNCTION public.olivia_prepare_welcome()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j public.olivia_integration_jobs; vid uuid; mid uuid; did uuid; cfg jsonb; created_count int:=0;
begin
 select value into cfg from public.olivia_config where key='bf2026';
 if not coalesce((cfg->>'whatsapp_template_approved')::boolean,false) or nullif(cfg->>'whatsapp_template_name','') is null then
 return jsonb_build_object('prepared',0,'reason','Plantilla pendiente de aprobación/configuración'); end if;
 for j in select * from public.olivia_integration_jobs where kind='whatsapp_welcome' and status in ('pending','waiting_consent') order by created_at limit 25 for update skip locked loop
  if not exists(select 1 from public.contacts where id=j.contact_id and phone is not null and 'bf2026_early_access'=any(manual_tags) and coalesce(preferences#>>'{early_access,source}','')<>'conversation') then
   update public.olivia_integration_jobs set status='cancelled',updated_at=now() where id=j.id;continue;
  end if;
  if not exists(select 1 from public.contact_channel_consents where contact_id=j.contact_id and channel='whatsapp' and status='granted') then
   update public.olivia_integration_jobs set status='waiting_consent',updated_at=now() where id=j.id;continue;
  end if;
  select id into vid from public.conversations where contact_id=j.contact_id and channel='whatsapp' and status='open' order by updated_at desc limit 1;
  if vid is null then insert into public.conversations(contact_id,channel) values(j.contact_id,'whatsapp') returning id into vid; end if;
  insert into public.outbound_dispatches(contact_id,conversation_id,channel,delivery_type,payload,idempotency_key)
  values(j.contact_id,vid,'whatsapp','template',jsonb_build_object('prompt_version','bf26-v2','welcome_job_id',j.id),'welcome:'||j.id)
  on conflict(idempotency_key) where idempotency_key is not null do nothing returning id into did;
  update public.olivia_integration_jobs set status='completed',completed_at=now(),payload=jsonb_build_object('dispatch_id',did),updated_at=now() where id=j.id;
  created_count:=created_count+1;
 end loop;
 return jsonb_build_object('prepared',created_count);
end;$function$;

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
 'contact',jsonb_build_object('first_name',c.first_name,'email',c.email,'phone',c.phone,'stage',c.stage,'source',c.source,'tags',c.manual_tags,'preferences',c.preferences),
 'commercial_profile',coalesce(c.preferences->'commercial','{}'::jsonb),
 'commercial_entries',coalesce((select jsonb_agg(to_jsonb(e) order by e.updated_at desc) from (select * from public.contact_commercial_entries where contact_id=c.id order by updated_at desc limit 50)e),'[]'::jsonb),
 'score',public.olivia_contact_score(c.id),
 'lead_state',coalesce(c.preferences->'olivia','{}'::jsonb),
 'conversation',jsonb_build_object('status',v.status,'handoff_status',v.handoff_status),
 'channel_consents',coalesce((select jsonb_object_agg(channel,jsonb_build_object('status',status,'recorded_at',recorded_at)) from public.contact_channel_consents where contact_id=c.id),'{}'::jsonb),
 'campaign',(select value from public.olivia_config where key='bf2026'),
 'early_access_registered','bf2026_early_access'=any(c.manual_tags),
 'history',coalesce((select jsonb_agg(to_jsonb(h) order by created_at) from (select direction,body,created_at from public.messages where conversation_id=v.id order by created_at desc limit 20)h),'[]'::jsonb),
 'document_index',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'title',d.title,'packages',d.routing_packages,'product_ids',public.olivia_document_product_ids(d.id,d.catalog_product_id))) from public.product_documents d where d.approval_status='approved' and not d.routing_packages && array['internal_ops']),'[]'::jsonb),
 'products',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'stock_status',stock_status,'price',price,'synced_at',synced_at)) from public.catalog_products where status='publish'),'[]'::jsonb),
 'now',now()) into result
 from public.contacts c join public.conversations v on v.contact_id=c.id
 where c.id=(p->>'contact_id')::uuid and v.id=(p->>'conversation_id')::uuid;
 return coalesce(result,'{}'::jsonb);
end;$function$;


