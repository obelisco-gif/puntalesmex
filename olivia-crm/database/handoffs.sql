-- Human cases are independent of chat control and of customer marketing consent.
create table if not exists public.olivia_handoffs(
 id uuid primary key default gen_random_uuid(),contact_id uuid references public.contacts(id) on delete set null,
 conversation_id uuid references public.conversations(id) on delete set null,
 status text not null default 'requested' check(status in ('requested','active','resolved','cancelled')),
 priority text not null default 'high' check(priority in ('low','normal','high','urgent')),
 reason text not null,summary text not null default '',source text not null check(source in ('olivia','crm','import')),
 assigned_to text,internal_notes text not null default '',contact_snapshot jsonb not null default '{}',
 notification_requested boolean not null default true,notification_dispatch_id uuid references public.outbound_dispatches(id) on delete set null,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),resolved_at timestamptz
);
create unique index if not exists olivia_one_open_handoff on public.olivia_handoffs(conversation_id) where status in ('requested','active');
create index if not exists olivia_handoff_directory on public.olivia_handoffs(created_at desc,id desc);
create index if not exists olivia_handoff_dispatch on public.olivia_handoffs(notification_dispatch_id);
create index if not exists olivia_handoff_contact on public.olivia_handoffs(contact_id);
create table if not exists public.olivia_handoff_events(
 id uuid primary key default gen_random_uuid(),handoff_id uuid not null references public.olivia_handoffs(id) on delete cascade,
 event_type text not null,actor text not null,metadata jsonb not null default '{}',created_at timestamptz not null default now()
);
create index if not exists olivia_handoff_event_history on public.olivia_handoff_events(handoff_id,created_at,id);
alter table public.olivia_handoffs enable row level security;
alter table public.olivia_handoff_events enable row level security;
revoke all on public.olivia_handoffs,public.olivia_handoff_events from public,anon,authenticated;
grant select,insert,update,delete on public.olivia_handoffs,public.olivia_handoff_events to service_role;

insert into public.olivia_config(key,value) values('handoff_alerts',jsonb_build_object(
 'enabled',false,'recipient_phone',null,'recipient_confirmed',false,
 'template_name','olivia_handoff_equipo','template_language','es','template_approved',false,
 'crm_base_url','https://olivia-crm-weld.vercel.app',
 'template_body',E'Olivia necesita ayuda del equipo Sadiet.\nContacto: {{1}}\nTeléfono: {{2}}\nMotivo: {{3}}\nResumen: {{4}}\nFicha: {{5}}\nTipo: {{6}}')) on conflict(key) do nothing;

create or replace function public.olivia_register_handoff(p_conversation uuid,p_source text,p_reason text default '',p_summary text default '') returns uuid
language plpgsql set search_path='' as $$
declare v public.conversations;c public.contacts; h public.olivia_handoffs; new_id uuid; target text;
begin
 if p_source not in ('olivia','crm','import') then raise exception 'Origen no válido'; end if;
 select * into v from public.conversations where id=p_conversation for update;
 if not found then raise exception 'Conversación no encontrada'; end if;
 select * into c from public.contacts where id=v.contact_id;
 if not found or c.source='qa_test' then return null; end if;
 target:=case when v.handoff_status='human' then 'active' else 'requested' end;
 select * into h from public.olivia_handoffs where conversation_id=v.id and status in ('requested','active') for update;
 if found then
  update public.olivia_handoffs set status=case when target='active' then 'active' else status end,
   summary=case when nullif(btrim(p_summary),'') is not null then left(p_summary,3000) else summary end,
   updated_at=clock_timestamp() where id=h.id;
  insert into public.olivia_handoff_events(handoff_id,event_type,actor,metadata)
  values(h.id,case when target='active' and h.status='requested' then 'taken_over' else 'context_updated' end,p_source,jsonb_build_object('status',target));
  return h.id;
 end if;
 insert into public.olivia_handoffs(contact_id,conversation_id,status,priority,reason,summary,source,assigned_to,notification_requested,contact_snapshot)
 values(c.id,v.id,target,v.priority,coalesce(nullif(left(btrim(p_reason),600),''),'Requiere revisión del equipo'),
 left(coalesce(nullif(btrim(p_summary),''),c.preferences#>>'{olivia,summary}','Sin resumen disponible'),3000),p_source,c.assigned_to,p_source<>'import',
 jsonb_build_object('name',coalesce(c.first_name,'Sin nombre confirmado'),'phone',c.phone,'email',c.email,'stage',c.stage,'tags',c.manual_tags,'score',public.olivia_contact_score(c.id)->'value')) returning id into new_id;
 insert into public.olivia_handoff_events(handoff_id,event_type,actor,metadata) values(new_id,'created',p_source,jsonb_build_object('status',target));
 return new_id;
end;$$;

create or replace function public.olivia_handoff_from_agent() returns trigger language plpgsql set search_path='' as $$
begin
 if new.agent_role='conversation' and new.status in ('completed','skipped') and coalesce((new.decision->>'needs_human')::boolean,false)
 and not coalesce((new.decision->>'opt_out')::boolean,false)
 and exists(select 1 from public.conversations where id=new.conversation_id and handoff_status in ('pending_human','human')) then
 perform public.olivia_register_handoff(new.conversation_id,'olivia',coalesce(nullif(new.decision->>'handoff_reason',''),case new.decision->>'intent' when 'order' then 'Consulta de pedido que requiere revisión' when 'product' then 'Consulta de producto que requiere revisión' when 'support' then 'Solicitud de soporte al equipo' else 'Solicitud de atención humana' end),new.decision->>'summary');
 end if;
 return new;
end;$$;
drop trigger if exists olivia_handoff_agent_run on public.agent_runs;
create trigger olivia_handoff_agent_run after insert on public.agent_runs for each row execute function public.olivia_handoff_from_agent();

create or replace function public.olivia_handoff_from_control() returns trigger language plpgsql set search_path='' as $$
begin
 if new.handoff_status='human' and old.handoff_status is distinct from 'human' then
 perform public.olivia_register_handoff(new.id,'crm','Intervención manual del equipo','');
 end if;
 return new;
end;$$;
drop trigger if exists olivia_handoff_control on public.conversations;
create trigger olivia_handoff_control after update of handoff_status on public.conversations for each row execute function public.olivia_handoff_from_control();

create or replace function public.olivia_handoff_settings() returns jsonb language sql set search_path='' as $$
 select jsonb_build_object('enabled',coalesce((value->>'enabled')::boolean,false),'recipient_configured',nullif(value->>'recipient_phone','') is not null and coalesce((value->>'recipient_confirmed')::boolean,false),'template_name',value->>'template_name','template_language',value->>'template_language','template_approved',coalesce((value->>'template_approved')::boolean,false),'template_body',value->>'template_body') from public.olivia_config where key='handoff_alerts';
$$;

create or replace function public.olivia_handoff_directory(p_page integer default 1,p_status text default '',p_search text default '') returns jsonb
language plpgsql set search_path='' as $$
declare total integer; page integer; items jsonb;
begin
 if p_status not in ('','requested','active','resolved','cancelled') then raise exception 'Estado no válido'; end if;
 select count(*) into total from public.olivia_handoffs h where (p_status='' or h.status=p_status)
 and concat_ws(' ',h.contact_snapshot->>'name',h.contact_snapshot->>'phone',h.contact_snapshot->>'email',h.reason,h.summary) ilike '%'||left(p_search,100)||'%';
 page:=least(greatest(1,coalesce(p_page,1)),greatest(1,ceil(total/50.0)::integer));
 select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc),'[]') into items from(
 select h.*,d.status as notification_status,d.error_message as notification_error,
 coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at,e.id) from public.olivia_handoff_events e where e.handoff_id=h.id),'[]') as events
 from public.olivia_handoffs h left join public.outbound_dispatches d on d.id=h.notification_dispatch_id
 where (p_status='' or h.status=p_status) and concat_ws(' ',h.contact_snapshot->>'name',h.contact_snapshot->>'phone',h.contact_snapshot->>'email',h.reason,h.summary) ilike '%'||left(p_search,100)||'%'
 order by h.created_at desc,h.id desc limit 50 offset (page-1)*50)r;
 return jsonb_build_object('total',total,'rows',items,'page',page,'page_size',50,'settings',public.olivia_handoff_settings());
end;$$;

create or replace function public.olivia_save_handoff(p_id uuid,p_input jsonb,p_actor uuid) returns jsonb
language plpgsql set search_path='' as $$
declare h public.olivia_handoffs; target text;
begin
 select * into h from public.olivia_handoffs where id=p_id for no key update;
 if not found then raise exception 'Derivación no encontrada'; end if;
 if p_actor is null or (p_input->>'expected_updated_at')::timestamptz is distinct from h.updated_at then raise exception 'La derivación ha cambiado'; end if;
 target:=coalesce(p_input->>'status',h.status);
 if target not in ('requested','active','resolved','cancelled') or (h.status in ('resolved','cancelled') and target not in ('resolved','cancelled')) then raise exception 'Estado no válido'; end if;
 update public.olivia_handoffs set status=target,assigned_to=nullif(left(btrim(coalesce(p_input->>'assigned_to',assigned_to)),100),''),internal_notes=left(coalesce(p_input->>'internal_notes',internal_notes),10000),resolved_at=case when target in ('resolved','cancelled') then coalesce(resolved_at,now()) else null end,updated_at=clock_timestamp() where id=p_id returning * into h;
 if target in ('resolved','cancelled') then
 update public.outbound_dispatches set status='cancelled',error_message='Derivación cerrada antes de enviar el aviso' where id=h.notification_dispatch_id and status='pending';
 end if;
 insert into public.olivia_handoff_events(handoff_id,event_type,actor,metadata) values(h.id,'crm_updated',p_actor::text,jsonb_build_object('status',h.status,'assigned_to',h.assigned_to,'internal_notes',h.internal_notes));
 return to_jsonb(h);
end;$$;

create or replace function public.olivia_prepare_handoff_notifications() returns jsonb
language plpgsql set search_path='' as $$
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
  select jsonb_build_array(jsonb_build_object('type','body','parameters',(select jsonb_agg(jsonb_build_object('type','text','text',x)) from jsonb_array_elements_text(params)x)),jsonb_build_object('type','button','sub_type','url','index','0','parameters',jsonb_build_array(jsonb_build_object('type','text','text',h.conversation_id::text)))) into components;
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
end;$$;

create or replace function public.olivia_handoff_delivery_event() returns trigger language plpgsql set search_path='' as $$
begin
 if new.payload->>'kind'='human_handoff_alert' and new.status is distinct from old.status then
 insert into public.olivia_handoff_events(handoff_id,event_type,actor,metadata)
 select id,'notification_'||new.status,'outbound',jsonb_build_object('dispatch_id',new.id,'error',new.error_message) from public.olivia_handoffs where notification_dispatch_id=new.id;
 end if;return new;
end;$$;
drop trigger if exists olivia_handoff_delivery on public.outbound_dispatches;
create trigger olivia_handoff_delivery after update of status on public.outbound_dispatches for each row execute function public.olivia_handoff_delivery_event();

-- Import existing human cases for visibility; never alert retrospectively.
do $$ declare v record;begin
 for v in select id from public.conversations where handoff_status in ('human','pending_human') loop
 perform public.olivia_register_handoff(v.id,'import','Caso previo a la puesta en marcha del registro','');
 end loop;
end;$$;

revoke all on function public.olivia_register_handoff(uuid,text,text,text),public.olivia_handoff_from_agent(),public.olivia_handoff_from_control(),public.olivia_handoff_settings(),public.olivia_handoff_directory(integer,text,text),public.olivia_save_handoff(uuid,jsonb,uuid),public.olivia_prepare_handoff_notifications(),public.olivia_handoff_delivery_event() from public,anon,authenticated;
grant execute on function public.olivia_register_handoff(uuid,text,text,text),public.olivia_handoff_from_agent(),public.olivia_handoff_from_control(),public.olivia_handoff_settings(),public.olivia_handoff_directory(integer,text,text),public.olivia_save_handoff(uuid,jsonb,uuid),public.olivia_prepare_handoff_notifications(),public.olivia_handoff_delivery_event() to service_role;
