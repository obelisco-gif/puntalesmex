CREATE OR REPLACE FUNCTION public.olivia_enqueue_tag_jobs()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if tg_op='UPDATE' and new.email is distinct from old.email then
  update public.olivia_integration_jobs set status='cancelled',last_error='Correo sustituido por petición del contacto',updated_at=clock_timestamp()
  where contact_id=new.id and kind='klaviyo_early_access' and status in ('pending','processing','waiting_consent');
 end if;
 if 'bf2026_early_access'=any(new.manual_tags) then
   insert into public.olivia_integration_jobs(contact_id,kind,idempotency_key,payload)
   values(new.id,'klaviyo_early_access','bf2026:'||new.id||':klaviyo:'||md5(coalesce(lower(new.email),'')),jsonb_build_object('email',lower(new.email)))
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
revoke all on function public.olivia_enqueue_tag_jobs() from public,anon,authenticated;
grant execute on function public.olivia_enqueue_tag_jobs() to service_role;CREATE OR REPLACE FUNCTION public.olivia_claim_integration(p_kind text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j public.olivia_integration_jobs; c public.contacts; cfg jsonb; channel_name text; consent public.contact_channel_consents;
begin
 select value into cfg from public.olivia_config where key='bf2026';
 if p_kind='whatsapp_welcome' then return; end if;
 if not coalesce((cfg->>'klaviyo_sync_enabled')::boolean,false) then return; end if;
 for j in select * from public.olivia_integration_jobs where kind=p_kind and status='pending' and available_at<=now() order by created_at limit 1 for update skip locked loop
  select * into c from public.contacts where id=j.contact_id;
  if p_kind='klaviyo_early_access' and nullif(j.payload->>'email','') is not null and lower(j.payload->>'email') is distinct from lower(c.email) then
   update public.olivia_integration_jobs set status='cancelled',last_error='Correo de trabajo sustituido',updated_at=now() where id=j.id;continue;
  end if;
  if p_kind='klaviyo_early_access' and not ('bf2026_early_access'=any(c.manual_tags)) then
    update public.olivia_integration_jobs set status='cancelled',updated_at=now() where id=j.id; continue;
  end if;
  select * into consent from public.contact_channel_consents where contact_id=c.id and channel='email';
  if c.email is null or (p_kind='klaviyo_early_access' and coalesce(consent.status,'unknown')<>'granted') then
    update public.olivia_integration_jobs set status='waiting_consent',last_error='Email o permiso de email pendiente',updated_at=now() where id=j.id; continue;
  end if;
  if p_kind='klaviyo_unsubscribe' and coalesce(consent.status,'unknown')<>'revoked' then
    update public.olivia_integration_jobs set status='cancelled',updated_at=now() where id=j.id; continue;
  end if;
  update public.olivia_integration_jobs set status='processing',attempts=attempts+1,claimed_at=now(),claim_token=gen_random_uuid(),updated_at=now() where id=j.id returning * into j;
  return next jsonb_build_object('job_id',j.id,'claim_token',j.claim_token,'kind',j.kind,'contact_id',c.id,'email',c.email,'first_name',c.first_name,'phone',c.phone,'consent_at',consent.recorded_at,'list_id',cfg->>'klaviyo_list_id','job_payload',j.payload);
 end loop;
end;$function$;
revoke all on function public.olivia_claim_integration(text) from public,anon,authenticated;
grant execute on function public.olivia_claim_integration(text) to service_role;CREATE OR REPLACE FUNCTION public.olivia_email_signup_status(p_contact uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare c public.contacts;j public.olivia_integration_jobs;permission text;state text;reason text;
begin
 select * into c from public.contacts where id=p_contact;
 if not found then return '{}'::jsonb;end if;
 select status into permission from public.contact_channel_consents where contact_id=c.id and channel='email';
 select * into j from public.olivia_integration_jobs where contact_id=c.id and kind='klaviyo_early_access' and (nullif(payload->>'email','') is null or lower(payload->>'email')=lower(c.email)) order by created_at desc,id desc limit 1;
 state:=case when c.email is null then 'no_email' when permission is distinct from 'granted' then 'consent_missing'
 when j.status='completed' and j.payload->>'membership_confirmed'='true' then 'confirmed'
 when j.status='blocked' then 'blocked' when j.status='failed' then 'failed'
 when j.status in ('pending','processing','waiting_consent') then 'pending' else 'not_requested' end;
 reason:=case when state in ('blocked','failed') then j.last_error else null end;
 return jsonb_build_object('email',c.email,'status',state,'membership_confirmed',state='confirmed','consent_recorded',permission='granted',
 'reason_code',j.payload->>'block_reason','reason',reason,'last_checked_at',j.updated_at);
end;$function$;
revoke all on function public.olivia_email_signup_status(uuid) from public,anon,authenticated;
grant execute on function public.olivia_email_signup_status(uuid) to service_role;
