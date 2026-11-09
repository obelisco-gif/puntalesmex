-- The receiver must validate Meta's HMAC before invoking this service-only function.
-- No events are reconstructed from historical dispatches.
alter table public.outbound_dispatches add column if not exists whatsapp_waba_id text;
alter table public.outbound_dispatches add column if not exists whatsapp_phone_number_id text;

create table if not exists public.olivia_whatsapp_status_events (
 id bigint generated always as identity primary key,
 waba_id text not null,
 phone_number_id text not null,
 whatsapp_message_id text not null,
 event_status text not null check(event_status in ('sent','delivered','read','failed')),
 occurred_at timestamptz not null,
 error_code text,
 error_title text,
 received_at timestamptz not null default now(),
 unique(waba_id,phone_number_id,whatsapp_message_id,event_status,occurred_at)
);
alter table public.olivia_whatsapp_status_events enable row level security;
revoke all on public.olivia_whatsapp_status_events from public,anon,authenticated;
grant select,insert on public.olivia_whatsapp_status_events to service_role;

create or replace function public.olivia_snapshot_whatsapp_sender()
returns trigger language plpgsql set search_path='' as $$
declare cfg jsonb;
begin
 if new.channel='whatsapp' and new.status='processing' and old.status is distinct from 'processing' then
  select value into cfg from public.olivia_config where key='bf2026';
  new.whatsapp_phone_number_id:=coalesce(new.whatsapp_phone_number_id,nullif(cfg->>'whatsapp_phone_number_id',''));
  new.whatsapp_waba_id:=coalesce(new.whatsapp_waba_id,nullif(cfg->>'whatsapp_waba_id',''));
 end if;
 return new;
end $$;
drop trigger if exists olivia_outbound_sender_snapshot on public.outbound_dispatches;
create trigger olivia_outbound_sender_snapshot before update of status on public.outbound_dispatches
for each row execute function public.olivia_snapshot_whatsapp_sender();

create or replace function public.olivia_record_whatsapp_status(
 p_waba_id text,p_phone_number_id text,p_message_id text,p_status text,
 p_occurred_at timestamptz,p_error_code text default null,p_error_title text default null
) returns boolean language plpgsql security definer set search_path='' as $$
declare cfg jsonb; changed integer;
begin
 select value into cfg from public.olivia_config where key='bf2026';
 if p_waba_id is null or p_phone_number_id is null
  or p_waba_id is distinct from nullif(cfg->>'whatsapp_waba_id','')
  or p_phone_number_id is distinct from nullif(cfg->>'whatsapp_phone_number_id','') then
  raise exception 'Cuenta de WhatsApp no autorizada';
 end if;
 if coalesce(length(p_message_id),0) not between 8 and 255 or p_status not in ('sent','delivered','read','failed')
  or p_occurred_at is null or p_occurred_at > now()+interval '10 minutes' then
  raise exception 'Evento no válido';
 end if;
 insert into public.olivia_whatsapp_status_events(waba_id,phone_number_id,whatsapp_message_id,event_status,occurred_at,error_code,error_title)
 values(p_waba_id,p_phone_number_id,p_message_id,p_status,p_occurred_at,left(p_error_code,40),left(p_error_title,300))
 on conflict(waba_id,phone_number_id,whatsapp_message_id,event_status,occurred_at) do nothing;
 get diagnostics changed=row_count;
 return changed=1;
end $$;
revoke all on function public.olivia_record_whatsapp_status(text,text,text,text,timestamptz,text,text) from public,anon,authenticated;
grant execute on function public.olivia_record_whatsapp_status(text,text,text,text,timestamptz,text,text) to service_role;

create or replace function public.olivia_whatsapp_source_allowed(p_waba_id text,p_phone_number_id text)
returns boolean language sql stable set search_path='' as $$
 select coalesce(nullif(value->>'whatsapp_waba_id','')=p_waba_id
  and nullif(value->>'whatsapp_phone_number_id','')=p_phone_number_id,false)
 from public.olivia_config where key='bf2026'
$$;
revoke all on function public.olivia_whatsapp_source_allowed(text,text) from public,anon,authenticated;
grant execute on function public.olivia_whatsapp_source_allowed(text,text) to service_role;

create or replace function public.olivia_whatsapp_delivery(p_message_id uuid)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object(
  'status',case
   when bool_or(e.event_status='read') then 'read'
   when bool_or(e.event_status='delivered') then 'delivered'
   when bool_or(e.event_status='failed') then 'failed'
   when bool_or(e.event_status='sent') then 'sent'
   else d.status end,
  'sent_at',min(e.occurred_at) filter(where e.event_status='sent'),
  'delivered_at',min(e.occurred_at) filter(where e.event_status='delivered'),
  'read_at',min(e.occurred_at) filter(where e.event_status='read'),
  'error',coalesce((array_agg(concat_ws(': ',e.error_code,e.error_title) order by e.occurred_at desc) filter(where e.event_status='failed'))[1],d.error_message))
 from public.outbound_dispatches d
 left join public.olivia_whatsapp_status_events e on e.whatsapp_message_id=d.external_dispatch_id
  and e.waba_id=d.whatsapp_waba_id and e.phone_number_id=d.whatsapp_phone_number_id
 where d.message_id=p_message_id and d.channel='whatsapp'
 group by d.id,d.status,d.error_message
 order by max(d.created_at) desc limit 1
$$;
revoke all on function public.olivia_whatsapp_delivery(uuid) from public,anon,authenticated;
grant execute on function public.olivia_whatsapp_delivery(uuid) to service_role;

create or replace function public.olivia_conversation_delivery_statuses(p_conversation_id uuid,p_message_ids uuid[])
returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_object_agg(m.id::text,public.olivia_whatsapp_delivery(m.id)),'{}'::jsonb)
 from public.messages m
 where m.conversation_id=p_conversation_id and m.direction='outbound' and m.id=any(p_message_ids)
$$;
revoke all on function public.olivia_conversation_delivery_statuses(uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.olivia_conversation_delivery_statuses(uuid,uuid[]) to service_role;
