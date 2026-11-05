CREATE OR REPLACE FUNCTION public.olivia_prepare_welcome()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j public.olivia_integration_jobs; vid uuid; mid uuid; did uuid; cfg jsonb; created_count int:=0; lead_name text;
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
  select left(coalesce(nullif(btrim(regexp_replace(first_name,'\s+',' ','g')),''),'👋'),60) into lead_name from public.contacts where id=j.contact_id;
  insert into public.outbound_dispatches(contact_id,conversation_id,channel,delivery_type,payload,idempotency_key)
  values(j.contact_id,vid,'whatsapp','template',jsonb_build_object('prompt_version','bf26-v2','kind','early_access_welcome','welcome_job_id',j.id,'template_name',cfg->>'whatsapp_template_name','template_language',coalesce(cfg->>'whatsapp_template_language','es'),'template_components',jsonb_build_array(jsonb_build_object('type','body','parameters',jsonb_build_array(jsonb_build_object('type','text','text',lead_name))))),'welcome:'||j.id)
  on conflict(idempotency_key) where idempotency_key is not null do nothing returning id into did;
  update public.olivia_integration_jobs set status='completed',completed_at=now(),payload=jsonb_build_object('dispatch_id',did),updated_at=now() where id=j.id;
  created_count:=created_count+1;
 end loop;
 return jsonb_build_object('prepared',created_count);
end;$function$;
revoke all on function public.olivia_prepare_welcome() from public,anon,authenticated;
grant execute on function public.olivia_prepare_welcome() to service_role;

