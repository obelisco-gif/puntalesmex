-- The disclosure is deterministic, once per contact, and confirmed by the provider.
alter table public.contacts add column if not exists ai_disclosure_shown boolean not null default false;
alter table public.contacts add column if not exists ai_disclosure_shown_at timestamptz;
alter table public.contacts add column if not exists ai_disclosure_version text;
alter table public.contacts add column if not exists ai_disclosure_dispatch_id uuid;
alter table public.contacts add column if not exists ai_disclosure_external_id text;
insert into public.olivia_config(key,value) values('ai_disclosure',jsonb_build_object('text','Nota: este chat puede contar con apoyo de ia','version','v1','template_name','olivia_aviso_ia','template_language','es','template_approved',false)) on conflict(key) do nothing;

create or replace function public.olivia_ensure_ai_disclosure(p_contact uuid,p_conversation uuid,p_payload jsonb,p_created timestamptz,p_message uuid,p_response uuid) returns uuid
language plpgsql set search_path='' as $$
declare c public.contacts;d public.outbound_dispatches;cfg jsonb;mid uuid;did uuid;stamp timestamptz;
begin
 select * into c from public.contacts where id=p_contact for update;
 if not found or c.ai_disclosure_shown then return null; end if;
 if c.ai_disclosure_dispatch_id is not null then
  select * into d from public.outbound_dispatches where id=c.ai_disclosure_dispatch_id;
  if found and d.status<>'cancelled' then return d.id; end if;
 end if;
 select value into cfg from public.olivia_config where key='ai_disclosure';
 stamp:=coalesce((select created_at from public.messages where id=p_message),p_created,now())-interval '1 microsecond';
 insert into public.messages(conversation_id,direction,body,created_at) values(p_conversation,'outbound',cfg->>'text',stamp) returning id into mid;
 insert into public.outbound_dispatches(contact_id,conversation_id,message_id,channel,delivery_type,payload,idempotency_key,created_at,scheduled_for)
 values(c.id,p_conversation,mid,'whatsapp','freeform',jsonb_build_object('kind','ai_disclosure','initial_response_id',p_response,'sender_role','assistant','prompt_version','bf26-v2','body',cfg->>'text','disclosure_version',cfg->>'version','optout_confirmation',coalesce((p_payload->>'optout_confirmation')::boolean,false)),
 'ai-disclosure:'||c.id||':'||mid,coalesce(p_created,now())-interval '1 microsecond',now()) returning id into did;
 update public.contacts set ai_disclosure_dispatch_id=did,preferences=jsonb_set(preferences,'{ai_disclosure}',jsonb_build_object('notified',false,'status','pending','version',cfg->>'version','text',cfg->>'text','dispatch_id',did)),updated_at=clock_timestamp() where id=c.id;
 return did;
end;$$;

create or replace function public.olivia_disclosure_before_outbound() returns trigger language plpgsql set search_path='' as $$
declare did uuid;
begin
 if new.channel='whatsapp' and new.contact_id is not null and new.conversation_id is not null
 and new.payload->>'prompt_version'='bf26-v2' and new.payload->>'sender_role' is distinct from 'human'
 and coalesce(new.payload->>'kind','') not in ('human_handoff_alert','ai_disclosure') then
  did:=public.olivia_ensure_ai_disclosure(new.contact_id,new.conversation_id,new.payload,new.created_at,new.message_id,new.id);
  if did is not null then new.payload:=new.payload||jsonb_build_object('ai_disclosure_dispatch_id',did); end if;
 end if;
 return new;
end;$$;
drop trigger if exists olivia_ai_disclosure_before_outbound on public.outbound_dispatches;
create trigger olivia_ai_disclosure_before_outbound before insert on public.outbound_dispatches for each row execute function public.olivia_disclosure_before_outbound();

create or replace function public.olivia_disclosure_delivery() returns trigger language plpgsql set search_path='' as $$
declare c public.contacts;
begin
 if new.payload->>'kind' is distinct from 'ai_disclosure' then return new; end if;
 select * into c from public.contacts where id=new.contact_id for no key update;
 if not found then return new; end if;
 if new.status in ('sent','delivered') and nullif(new.external_dispatch_id,'') is not null and new.error_message is null and not c.ai_disclosure_shown then
  update public.contacts set ai_disclosure_shown=true,ai_disclosure_shown_at=clock_timestamp(),ai_disclosure_version=new.payload->>'disclosure_version',ai_disclosure_external_id=new.external_dispatch_id,
  preferences=jsonb_set(preferences,'{ai_disclosure}',jsonb_build_object('notified',true,'status',new.status,'notified_at',clock_timestamp(),'version',new.payload->>'disclosure_version','text',new.payload->>'body','dispatch_id',new.id,'external_id',new.external_dispatch_id)),updated_at=clock_timestamp() where id=c.id;
  insert into public.contact_events(contact_id,event_type,source,metadata,idempotency_key) values(c.id,'ai_disclosure_sent','outbound',jsonb_build_object('dispatch_id',new.id,'external_id',new.external_dispatch_id,'version',new.payload->>'disclosure_version'),'ai-disclosure-sent:'||c.id) on conflict(idempotency_key) do nothing;
 elsif not c.ai_disclosure_shown and c.ai_disclosure_dispatch_id=new.id then
  update public.contacts set preferences=jsonb_set(preferences,'{ai_disclosure,status}',to_jsonb(new.status)),updated_at=clock_timestamp() where id=c.id;
 end if;
 return new;
end;$$;
drop trigger if exists olivia_ai_disclosure_delivery on public.outbound_dispatches;
create trigger olivia_ai_disclosure_delivery after update of status on public.outbound_dispatches for each row execute function public.olivia_disclosure_delivery();

create or replace function public.complete_olivia_outbound(p_dispatch_id uuid,p_external_dispatch_id text default null,p_error_message text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare problem text:=coalesce(nullif(p_error_message,''),case when nullif(p_external_dispatch_id,'') is null then 'Sin identificador confirmado de WhatsApp; revisar antes de reintentar' end);
begin
 update public.outbound_dispatches set status=case when problem is null then 'sent' else 'failed' end,external_dispatch_id=p_external_dispatch_id,error_message=problem,sent_at=case when problem is null then now() else sent_at end where id=p_dispatch_id and status='processing';
 return p_dispatch_id;
end;$$;

-- Pending automated responses created before this migration get the same protection.
do $$ declare d record;did uuid;begin
 for d in select * from public.outbound_dispatches where status='pending' and channel='whatsapp' and contact_id is not null and conversation_id is not null and payload->>'prompt_version'='bf26-v2' and payload->>'sender_role' is distinct from 'human' and coalesce(payload->>'kind','') not in ('human_handoff_alert','ai_disclosure') order by created_at,id loop
  did:=public.olivia_ensure_ai_disclosure(d.contact_id,d.conversation_id,d.payload,d.created_at,d.message_id,d.id);
  if did is not null then update public.outbound_dispatches set payload=payload||jsonb_build_object('ai_disclosure_dispatch_id',did) where id=d.id; end if;
 end loop;
end;$$;
revoke all on function public.olivia_ensure_ai_disclosure(uuid,uuid,jsonb,timestamptz,uuid,uuid),public.olivia_disclosure_before_outbound(),public.olivia_disclosure_delivery(),public.complete_olivia_outbound(uuid,text,text) from public,anon,authenticated;
grant execute on function public.olivia_ensure_ai_disclosure(uuid,uuid,jsonb,timestamptz,uuid,uuid),public.olivia_disclosure_before_outbound(),public.olivia_disclosure_delivery(),public.complete_olivia_outbound(uuid,text,text) to service_role;
