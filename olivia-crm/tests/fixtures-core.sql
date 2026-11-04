
create table if not exists public.olivia_config (
 key text primary key, value jsonb not null, updated_at timestamptz not null default now()
);
alter table public.olivia_config enable row level security;
create table if not exists public.contact_channel_consents (
 contact_id uuid not null references public.contacts(id) on delete cascade,
 channel text not null check(channel in ('email','whatsapp')),
 status text not null check(status in ('granted','revoked','unknown')),
 recorded_at timestamptz not null default now(), source text not null,
 evidence jsonb not null default '{}'::jsonb,
 primary key(contact_id,channel)
);
alter table public.contact_channel_consents enable row level security;
create table if not exists public.olivia_integration_jobs (
 id uuid primary key default gen_random_uuid(), contact_id uuid not null references public.contacts(id) on delete cascade,
 kind text not null check(kind in ('klaviyo_early_access','whatsapp_welcome','klaviyo_unsubscribe')),
 campaign text not null default 'bf2026_early_access',
 status text not null default 'pending' check(status in ('pending','processing','completed','waiting_consent','blocked','failed','cancelled')),
 idempotency_key text not null unique, payload jsonb not null default '{}'::jsonb,
 attempts integer not null default 0, available_at timestamptz not null default now(),
 claimed_at timestamptz, claim_token uuid, completed_at timestamptz, last_error text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.olivia_integration_jobs enable row level security;
create index if not exists olivia_jobs_ready on public.olivia_integration_jobs(kind,available_at) where status='pending';
create index if not exists olivia_jobs_contact on public.olivia_integration_jobs(contact_id);
alter table public.product_documents add column if not exists routing_packages text[] not null default array['reference']::text[];
alter table public.product_documents add column if not exists document_key text;
create unique index if not exists olivia_document_key on public.product_documents(document_key) where document_key is not null;
alter table public.outbound_dispatches add column if not exists idempotency_key text;
create unique index if not exists olivia_dispatch_idempotency on public.outbound_dispatches(idempotency_key) where idempotency_key is not null;
insert into public.olivia_config(key,value) values ('bf2026',
'{"campaign_tag":"bf2026_early_access","klaviyo_list_id":"TESTLIST","klaviyo_list_name":"Early access 26","stock_limited":true,"early_access_hours":24,"registration_open":true,"early_access_starts_at":null,"public_starts_at":null,"ends_at":null,"registration_url":null,"access_url":null,"whatsapp_outbound_enabled":false,"whatsapp_template_name":null,"whatsapp_template_language":"es","whatsapp_phone_number_id":"000000000000001","whatsapp_template_components":[],"whatsapp_template_approved":false,"klaviyo_sync_enabled":false,"email_sequence_ready":false}'::jsonb)
on conflict(key) do nothing;
revoke all on public.olivia_config,public.contact_channel_consents,public.olivia_integration_jobs from anon,authenticated;
grant all on public.olivia_config,public.contact_channel_consents,public.olivia_integration_jobs to service_role;

create or replace function public.olivia_enqueue_tag_jobs() returns trigger
language plpgsql security definer set search_path='' as $f$
begin
 if 'bf2026_early_access'=any(new.manual_tags) then
   insert into public.olivia_integration_jobs(contact_id,kind,idempotency_key)
   values(new.id,'klaviyo_early_access','bf2026:'||new.id||':klaviyo'),
         (new.id,'whatsapp_welcome','bf2026:'||new.id||':whatsapp')
   on conflict(idempotency_key) do update set
    status=case when public.olivia_integration_jobs.status='waiting_consent' then 'pending' else public.olivia_integration_jobs.status end,
    updated_at=now();
 else
   update public.olivia_integration_jobs set status='cancelled',updated_at=now()
   where contact_id=new.id and campaign='bf2026_early_access' and status in ('pending','waiting_consent');
 end if;
 return new;
end;$f$;
drop trigger if exists olivia_early_access_tag on public.contacts;
create trigger olivia_early_access_tag after insert or update of manual_tags,email,phone on public.contacts
for each row execute function public.olivia_enqueue_tag_jobs();

create or replace function public.olivia_consent_changed() returns trigger
language plpgsql security definer set search_path='' as $f$
begin
 if new.status='revoked' then
   update public.olivia_integration_jobs set status='cancelled',updated_at=now()
   where contact_id=new.contact_id and status in ('pending','waiting_consent')
   and kind=case when new.channel='whatsapp' then 'whatsapp_welcome' else 'klaviyo_early_access' end;
   update public.outbound_dispatches set status='cancelled',error_message='Permiso retirado',claimed_at=null
   where contact_id=new.contact_id and channel=new.channel and status in ('pending','processing');
   update public.follow_ups set status='cancelled' where contact_id=new.contact_id and channel=new.channel and status='pending';
   if new.channel='email' then
     insert into public.olivia_integration_jobs(contact_id,kind,idempotency_key,payload)
     values(new.contact_id,'klaviyo_unsubscribe','email-optout:'||new.contact_id||':'||new.recorded_at,
      jsonb_build_object('consent_at',new.recorded_at))
     on conflict(idempotency_key) do nothing;
   end if;
 elsif new.status='granted' then
   update public.olivia_integration_jobs set status='pending',available_at=now(),updated_at=now()
   where contact_id=new.contact_id and status='waiting_consent'
     and kind=case when new.channel='whatsapp' then 'whatsapp_welcome' else 'klaviyo_early_access' end;
 end if;
 return new;
end;$f$;
drop trigger if exists olivia_channel_consent on public.contact_channel_consents;
create trigger olivia_channel_consent after insert or update on public.contact_channel_consents
for each row execute function public.olivia_consent_changed();

create or replace function public.olivia_apply_optout(p_contact_id uuid,p_scope text,p_evidence text)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare ch text;
begin
 if p_scope not in ('whatsapp','email','all') then raise exception 'Invalid opt-out scope'; end if;
 for ch in select unnest(case when p_scope='all' then array['whatsapp','email'] else array[p_scope] end) loop
   insert into public.contact_channel_consents(contact_id,channel,status,source,evidence)
   values(p_contact_id,ch,'revoked','conversation',jsonb_build_object('request',left(p_evidence,1000)))
   on conflict(contact_id,channel) do update set status='revoked',recorded_at=now(),source='conversation',evidence=excluded.evidence;
 end loop;
 insert into public.contact_events(contact_id,event_type,source,metadata)
 values(p_contact_id,'channel_opt_out','olivia',jsonb_build_object('scope',p_scope));
 return jsonb_build_object('opt_out_recorded',true,'scope',p_scope);
end;$f$;

create or replace function public.olivia_ingest_lead_b64(p_payload_b64 text)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb;
 cid uuid; eid uuid; email_id uuid; phone_id uuid; ph text; em text; ch text; granted boolean; stamp timestamptz; existing_status text;
begin
 if nullif(p->>'external_lead_id','') is null then raise exception 'external_lead_id required'; end if;
 perform pg_advisory_xact_lock(hashtextextended('olivia-import:'||(p->>'external_lead_id'),0));
 select contact_id into cid from public.contact_events where idempotency_key='meta-lead:'||(p->>'external_lead_id');
 if cid is not null then return jsonb_build_object('contact_id',cid,'duplicate',true); end if;
 em:=nullif(lower(btrim(p->>'email')),'');
 ph:=nullif(regexp_replace(coalesce(p->>'phone',''),'[^0-9]','','g'),'');
 if left(ph,2)='00' then ph:=substr(ph,3); end if;
 if ph is not null then ph:='+'||ph; end if;
 if em is not null and em !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid email'; end if;
 if ph is not null and ph !~ '^\+[1-9][0-9]{6,14}$' then raise exception 'Phone must include country prefix'; end if;
 if em is null and ph is null then raise exception 'Email or phone required'; end if;
 if em is not null then perform pg_advisory_xact_lock(hashtextextended('olivia-email:'||em,0)); end if;
 if ph is not null then perform pg_advisory_xact_lock(hashtextextended('olivia-phone:'||ph,0)); end if;
 select id into email_id from public.contacts where lower(email)=em;
 select id into phone_id from public.contacts where regexp_replace(coalesce(phone,''),'[^0-9]','','g')=substr(ph,2) order by created_at limit 1;
 if email_id is not null and phone_id is not null and email_id<>phone_id then raise exception 'Identity conflict: manual review required'; end if;
 cid:=coalesce(email_id,phone_id);
 if cid is null then
   insert into public.contacts(email,phone,first_name,source) values(em,ph,nullif(left(p->>'first_name',100),''),'meta_lead_form') returning id into cid;
 else
   if exists(select 1 from public.contacts where id=cid and ((email is not null and em is not null and lower(email)<>em) or (phone is not null and ph is not null and regexp_replace(phone,'[^0-9]','','g')<>substr(ph,2)))) then
    raise exception 'Identity conflict: existing contact has different identifiers';
   end if;
   update public.contacts set email=coalesce(email,em),phone=coalesce(phone,ph),first_name=coalesce(first_name,nullif(left(p->>'first_name',100),'')),updated_at=now() where id=cid;
 end if;
 stamp:=coalesce(nullif(p->>'submitted_at','')::timestamptz,now());
 if stamp>now()+interval '5 minutes' then raise exception 'Invalid future submission time'; end if;
 for ch in select unnest(array['email','whatsapp']) loop
  granted:=coalesce((p->>('consent_'||ch))::boolean,false);
  if granted then
   if nullif(p->>'consent_text','') is null then raise exception 'Consent evidence required'; end if;
   insert into public.contact_channel_consents(contact_id,channel,status,recorded_at,source,evidence)
   values(cid,ch,'granted',stamp,'meta_lead_form',jsonb_build_object('external_lead_id',p->>'external_lead_id','form_id',p->>'form_id','text',p->>'consent_text'))
   on conflict(contact_id,channel) do update set status='granted',recorded_at=excluded.recorded_at,source=excluded.source,evidence=excluded.evidence
   where public.contact_channel_consents.recorded_at<excluded.recorded_at;
  end if;
 end loop;
 update public.contacts set manual_tags=array(select distinct unnest(manual_tags||array['bf2026_early_access'])),
  utm_source=coalesce(nullif(p->>'utm_source',''),utm_source,'meta'),
  utm_campaign=coalesce(nullif(p->>'utm_campaign',''),utm_campaign,'bf2026_early_access'),
  privacy_notice_accepted_at=case when coalesce((p->>'privacy_accepted')::boolean,false) then stamp else privacy_notice_accepted_at end,
  updated_at=now() where id=cid;
 insert into public.contact_events(contact_id,event_type,source,metadata,idempotency_key)
 values(cid,'early_access_registered','meta_lead_form',p-'phone'-'email'-'first_name','meta-lead:'||(p->>'external_lead_id')) returning id into eid;
 insert into public.attribution_touchpoints(contact_id,channel,source,campaign,external_lead_id,metadata)
 values(cid,'meta_lead_form','meta',coalesce(p->>'utm_campaign','bf2026_early_access'),p->>'external_lead_id',jsonb_build_object('form_id',p->>'form_id','ad_id',p->>'ad_id'));
 return jsonb_build_object('contact_id',cid,'registered',true,'tag','bf2026_early_access','duplicate',false);
end;$f$;

create or replace function public.olivia_context_v2_b64(p_payload_b64 text)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb; result jsonb;
begin
 select jsonb_build_object(
 'contact_id',c.id,'conversation_id',v.id,'batch_text',p->>'batch_text','batch_ids',coalesce(p->'batch_ids','[]'::jsonb),
 'contact',jsonb_build_object('first_name',c.first_name,'email',c.email,'phone',c.phone,'stage',c.stage,'source',c.source,'tags',c.manual_tags,'preferences',c.preferences),
 'lead_state',coalesce(c.preferences->'olivia','{}'::jsonb),
 'conversation',jsonb_build_object('status',v.status,'handoff_status',v.handoff_status),
 'channel_consents',coalesce((select jsonb_object_agg(channel,jsonb_build_object('status',status,'recorded_at',recorded_at)) from public.contact_channel_consents where contact_id=c.id),'{}'::jsonb),
 'campaign',(select value from public.olivia_config where key='bf2026'),
 'early_access_registered','bf2026_early_access'=any(c.manual_tags),
 'history',coalesce((select jsonb_agg(to_jsonb(h) order by created_at) from (select direction,body,created_at from public.messages where conversation_id=v.id order by created_at desc limit 20)h),'[]'::jsonb),
 'document_index',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'title',d.title,'packages',d.routing_packages)) from public.product_documents d where d.approval_status='approved'),'[]'::jsonb),
 'products',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'stock_status',stock_status,'price',price,'synced_at',synced_at)) from public.catalog_products where status='publish'),'[]'::jsonb),
 'now',now()) into result
 from public.contacts c join public.conversations v on v.contact_id=c.id
 where c.id=(p->>'contact_id')::uuid and v.id=(p->>'conversation_id')::uuid;
 return coalesce(result,'{}'::jsonb);
end;$f$;

create or replace function public.olivia_response_context_b64(p_payload_b64 text)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb;
 ctx jsonb; d jsonb:=coalesce(p->'decision','{}'); packages text[]; result jsonb;
begin
 ctx:=public.olivia_context_v2_b64(p_payload_b64);
 if ctx='{}'::jsonb then raise exception 'Contact/conversation mismatch'; end if;
 packages:=array(select jsonb_array_elements_text(coalesce(d->'knowledge_packages','[]')));
 select (ctx-'document_index'-'products')||jsonb_build_object(
 'decision',d,
 'documents',coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'content',content,'packages',routing_packages,'source_url',source_url))
  from public.product_documents where approval_status='approved'
  and (routing_packages && array['always','black_friday'] or routing_packages && packages)),'[]'::jsonb),
 'products',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'url',permalink,'price',price,'currency',currency,'stock_status',stock_status,'stock_quantity',stock_quantity,'synced_at',synced_at,'product_type',product_type))
  from public.catalog_products where status='publish' and id::text in (select jsonb_array_elements_text(coalesce(d->'product_ids','[]')))),'[]'::jsonb)
 ) into result;
 return result;
end;$f$;

create or replace function public.olivia_complete_v2_b64(p_payload_b64 text)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb;
 d jsonb:=coalesce(p->'decision','{}'); cid uuid:=(p->>'contact_id')::uuid; vid uuid:=(p->>'conversation_id')::uuid;
 mid uuid; did uuid; batch uuid[]:=array(select jsonb_array_elements_text(coalesce(p->'batch_ids','[]'))::uuid);
 opt boolean:=coalesce((d->>'opt_out')::boolean,false); human boolean:=coalesce((d->>'needs_human')::boolean,false);
 scope text:=coalesce(d->>'opt_out_scope','whatsapp'); reply text:=left(coalesce(p->>'reply_text',''),1600);
 key text;
begin
 perform 1 from public.conversations where id=vid and contact_id=cid for update;
 if not found then raise exception 'Contact/conversation mismatch'; end if;
 if cardinality(batch)=0 then raise exception 'Inbound batch required'; end if;
 if exists(select 1 from public.inbound_message_buffer where id=any(batch) and (contact_id<>cid or conversation_id<>vid)) then raise exception 'Invalid batch ownership'; end if;
 if (select count(*) from public.inbound_message_buffer where id=any(batch) and status='claimed')<>cardinality(batch) then
  return jsonb_build_object('duplicate_or_unclaimed',true);
 end if;
 key:='olivia-reply:'||md5(array_to_string(array(select unnest(batch) order by 1),','));
 if opt then
  if scope not in ('whatsapp','email','all') then scope:='whatsapp'; end if;
  perform public.olivia_apply_optout(cid,scope,coalesce(p->>'batch_text',''));
  if scope='whatsapp' then reply:='He registrado tu baja de los mensajes de WhatsApp de Sadiet.';
  elsif scope='email' then reply:='He registrado tu solicitud de baja de los emails de Sadiet.';
  else reply:='He registrado tu solicitud de baja de las comunicaciones de Sadiet.'; end if;
 elsif human then
  update public.conversations set handoff_status='pending_human',priority='high',updated_at=now() where id=vid;
 elsif exists(select 1 from public.conversations where id=vid and handoff_status in ('human','pending_human')) then
  reply:='';
 end if;
 update public.contacts set preferences=jsonb_set(preferences,'{olivia}',
  coalesce(preferences->'olivia','{}')||jsonb_build_object('summary',left(coalesce(d->>'summary',''),3000),'last_intent',d->>'intent','pending_question',d->>'pending_question','early_access_action',d->>'early_access_action','temperature',d->>'temperature','updated_at',now())),updated_at=now() where id=cid;
 insert into public.agent_runs(conversation_id,contact_id,inbound_batch_ids,agent_role,status,decision,prompt_version,input_summary,output_summary,completed_at)
 values(vid,cid,batch,'conversation',case when reply='' then 'skipped' else 'completed' end,d,'bf26-v2',left(p->>'batch_text',2000),reply,now());
 if reply<>'' and (opt or not exists(select 1 from public.contact_channel_consents where contact_id=cid and channel='whatsapp' and status='revoked')) then
  insert into public.messages(conversation_id,direction,body) values(vid,'outbound',reply) returning id into mid;
  insert into public.outbound_dispatches(contact_id,conversation_id,message_id,channel,delivery_type,payload,idempotency_key)
  values(cid,vid,mid,'whatsapp','freeform',jsonb_build_object('body',reply,'optout_confirmation',opt,'prompt_version','bf26-v2'),key)
  on conflict(idempotency_key) where idempotency_key is not null do nothing returning id into did;
 end if;
 update public.inbound_message_buffer set status='processed',processed_at=now() where id=any(batch) and status='claimed';
 return jsonb_build_object('saved',true,'dispatch_id',did,'opt_out_recorded',opt,'needs_human',human);
end;$f$;

create or replace function public.olivia_claim_integration(p_kind text)
returns setof jsonb language plpgsql security definer set search_path='' as $f$
declare j public.olivia_integration_jobs; c public.contacts; cfg jsonb; channel_name text; consent public.contact_channel_consents;
begin
 select value into cfg from public.olivia_config where key='bf2026';
 if p_kind='whatsapp_welcome' then return; end if;
 if not coalesce((cfg->>'klaviyo_sync_enabled')::boolean,false) then return; end if;
 for j in select * from public.olivia_integration_jobs where kind=p_kind and status='pending' and available_at<=now() order by created_at limit 1 for update skip locked loop
  select * into c from public.contacts where id=j.contact_id;
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
  return next jsonb_build_object('job_id',j.id,'claim_token',j.claim_token,'kind',j.kind,'contact_id',c.id,'email',c.email,'first_name',c.first_name,'phone',c.phone,'consent_at',consent.recorded_at,'list_id',cfg->>'klaviyo_list_id');
 end loop;
end;$f$;

create or replace function public.olivia_complete_integration_b64(p_payload_b64 text)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb; j public.olivia_integration_jobs;
begin
 update public.olivia_integration_jobs set
 status=case when coalesce((p->>'success')::boolean,false) then 'completed' else 'failed' end,
 completed_at=case when coalesce((p->>'success')::boolean,false) then now() else null end,
 payload=payload||coalesce(p->'result','{}'),last_error=nullif(left(p->>'error',1500),''),updated_at=now()
 where id=(p->>'job_id')::uuid and claim_token=(p->>'claim_token')::uuid and status='processing' returning * into j;
 if j.id is null then return jsonb_build_object('ignored',true); end if;
 insert into public.contact_events(contact_id,event_type,source,metadata,idempotency_key)
 values(j.contact_id,j.kind||'_'||j.status,'n8n',jsonb_build_object('job_id',j.id),j.id||':'||j.status)
 on conflict(idempotency_key) do nothing;
 return jsonb_build_object('job_id',j.id,'status',j.status);
end;$f$;

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
    or (conv.handoff_status='human') then
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

create or replace function public.olivia_prepare_welcome()
returns jsonb language plpgsql security definer set search_path='' as $f$
declare j public.olivia_integration_jobs; vid uuid; mid uuid; did uuid; cfg jsonb; created_count int:=0;
begin
 select value into cfg from public.olivia_config where key='bf2026';
 if not coalesce((cfg->>'whatsapp_template_approved')::boolean,false) or nullif(cfg->>'whatsapp_template_name','') is null then
 return jsonb_build_object('prepared',0,'reason','Plantilla pendiente de aprobación/configuración'); end if;
 for j in select * from public.olivia_integration_jobs where kind='whatsapp_welcome' and status in ('pending','waiting_consent') order by created_at limit 25 for update skip locked loop
  if not exists(select 1 from public.contacts where id=j.contact_id and 'bf2026_early_access'=any(manual_tags)) then
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
end;$f$;

do $p$ declare f record; begin
 for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'olivia_%') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.sig);
  execute format('grant execute on function %s to service_role',f.sig);
 end loop;
end;$p$;


CREATE OR REPLACE FUNCTION public.ingest_olivia_inbound(p_channel text, p_external_message_id text, p_external_thread_id text, p_phone text, p_body text, p_message_type text DEFAULT 'text'::text, p_media jsonb DEFAULT '[]'::jsonb, p_source_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(contact_id uuid, conversation_id uuid, buffer_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_contact_id uuid;
  v_conversation_id uuid;
  v_buffer_id uuid;
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
begin
  select c.id into v_contact_id
  from public.contacts c
  where regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g') = v_phone
  order by c.updated_at desc limit 1;
  if v_contact_id is null then
    insert into public.contacts(phone, stage, source, preferences)
    values (nullif(p_phone, ''), 'new', p_channel, '{}'::jsonb)
    returning id into v_contact_id;
  end if;
  select c.id into v_conversation_id from public.conversations c
  where c.contact_id=v_contact_id and c.channel=p_channel and c.status='open'
  order by c.updated_at desc limit 1;
  if v_conversation_id is null then
    insert into public.conversations(contact_id, channel, status, priority, handoff_status)
    values (v_contact_id, p_channel, 'open', 'normal', 'bot')
    returning id into v_conversation_id;
  else
    update public.conversations set updated_at=now() where id=v_conversation_id;
  end if;
  insert into public.messages(conversation_id,direction,body,external_message_id)
  values (v_conversation_id,'inbound',nullif(p_body,''),p_external_message_id)
  on conflict (external_message_id) where external_message_id is not null do nothing;
  insert into public.inbound_message_buffer(channel,external_message_id,external_thread_id,contact_id,conversation_id,message_type,normalized_text,media,source_payload)
  values (p_channel,p_external_message_id,p_external_thread_id,v_contact_id,v_conversation_id,coalesce(p_message_type,'text'),nullif(p_body,''),coalesce(p_media,'[]'::jsonb),coalesce(p_source_payload,'{}'::jsonb))
  on conflict (channel,external_message_id) do update set source_payload=excluded.source_payload
  returning id into v_buffer_id;
  return query select v_contact_id,v_conversation_id,v_buffer_id;
end; $function$;

