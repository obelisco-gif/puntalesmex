-- Admin-only CRM RPCs. No direct browser access to contact data.
create or replace function public.olivia_contact_detail(p_id uuid) returns jsonb
language sql set search_path='' as $$
 select to_jsonb(c)||jsonb_build_object(
 'purchase_history',public.olivia_purchase_history(c.id),
 'attribute_records',coalesce((select jsonb_agg(to_jsonb(a) order by attribute_key) from public.lead_attributes a where a.contact_id=c.id and status='confirmed'),'[]'),
 'preferences',jsonb_set(c.preferences,'{commercial}',public.olivia_commercial_profile(c.id)),
 'lead_state',(select to_jsonb(ls) from public.lead_states ls where ls.contact_id=c.id),
 'score',public.olivia_contact_score(c.id),
 'commercial_entries',coalesce((select jsonb_agg(to_jsonb(e) order by e.updated_at desc) from public.contact_commercial_entries e where e.contact_id=c.id),'[]'))
 from public.contacts c where c.id=p_id and coalesce(c.source,'')<>'qa_test';
$$;

create or replace function public.olivia_conversation_directory(p_page integer default 1,p_search text default '',p_status text default '',p_control text default '') returns jsonb
language plpgsql set search_path='' as $$
declare n integer; page integer; items jsonb;
begin
 if p_status not in ('','open','paused','closed') or p_control not in ('','bot','human','pending_human','resolved') then raise exception 'Filtro no válido'; end if;
 select count(*) into n from public.conversations v join public.contacts c on c.id=v.contact_id
 where coalesce(c.source,'')<>'qa_test' and (p_status='' or v.status=p_status) and (p_control='' or v.handoff_status=p_control)
 and (coalesce(c.first_name,'') ilike '%'||left(p_search,100)||'%' or coalesce(c.email,'') ilike '%'||left(p_search,100)||'%' or coalesce(c.phone,'') ilike '%'||left(p_search,100)||'%');
 page:=least(greatest(1,coalesce(p_page,1)),greatest(1,ceil(n/50.0)::integer));
 select coalesce(jsonb_agg(to_jsonb(r) order by r.updated_at desc,r.id desc),'[]') into items from (
 select v.*,jsonb_build_object('first_name',c.first_name,'email',c.email,'phone',c.phone,'stage',c.stage,'tags',c.manual_tags) as contact,
 coalesce(c.preferences->'olivia'->>'summary',m.body,'Sin resumen todavía') as preview,
 (public.olivia_contact_score(c.id)->>'value')::integer as score
 from public.conversations v join public.contacts c on c.id=v.contact_id
 left join lateral(select body from public.messages where conversation_id=v.id order by created_at desc,id desc limit 1)m on true
 where coalesce(c.source,'')<>'qa_test' and (p_status='' or v.status=p_status) and (p_control='' or v.handoff_status=p_control)
 and (coalesce(c.first_name,'') ilike '%'||left(p_search,100)||'%' or coalesce(c.email,'') ilike '%'||left(p_search,100)||'%' or coalesce(c.phone,'') ilike '%'||left(p_search,100)||'%')
 order by v.updated_at desc,v.id desc limit 50 offset (page-1)*50)r;
 return jsonb_build_object('rows',items,'total',n,'page',page,'page_size',50,
 'open_total',(select count(*) from public.conversations v join public.contacts c on c.id=v.contact_id where v.status='open' and coalesce(c.source,'')<>'qa_test'));
end;$$;

create or replace function public.olivia_conversation_detail(p_id uuid,p_before uuid default null) returns jsonb
language plpgsql set search_path='' as $$
declare v public.conversations; items jsonb; older boolean; cursor_time timestamptz; oldest_id uuid; oldest_time timestamptz;
begin
 select cv.* into v from public.conversations cv join public.contacts c on c.id=cv.contact_id where cv.id=p_id and coalesce(c.source,'')<>'qa_test';
 if not found then return null; end if;
 if p_before is not null then
 select created_at into cursor_time from public.messages where id=p_before and conversation_id=p_id;
 if not found then raise exception 'Cursor no válido'; end if;
 end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at,r.id),'[]') into items from (
 select m.*, (select d.status from public.outbound_dispatches d where d.message_id=m.id order by d.created_at desc,d.id desc limit 1) as delivery_status
 from public.messages m where m.conversation_id=p_id and (p_before is null or (m.created_at,m.id)<(cursor_time,p_before))
 order by m.created_at desc,m.id desc limit 50)r;
 oldest_id:=(items->0->>'id')::uuid; oldest_time:=(items->0->>'created_at')::timestamptz;
 select exists(select 1 from public.messages where conversation_id=p_id and (created_at,id)<(oldest_time,oldest_id)) into older;
 return jsonb_build_object('conversation',to_jsonb(v),'contact',public.olivia_contact_detail(v.contact_id),'messages',items,'has_older',older,
 'message_count',(select count(*) from public.messages where conversation_id=p_id),
 'channel_consents',coalesce((select jsonb_agg(jsonb_build_object('channel',channel,'status',status)) from public.contact_channel_consents where contact_id=v.contact_id),'[]'));
end;$$;

create or replace function public.olivia_save_conversation(p_id uuid,p_input jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare v public.conversations; target text; cancelled integer:=0; processing integer:=0;
begin
 select * into v from public.conversations where id=p_id for update;
 if not found then raise exception 'Conversación no encontrada'; end if;
 if p_input->>'expected_updated_at' is null or (p_input->>'expected_updated_at')::timestamptz is distinct from v.updated_at then raise exception 'La conversación ha cambiado'; end if;
 target:=coalesce(p_input->>'handoff_status',v.handoff_status);
 if target not in ('bot','human','pending_human','resolved') or coalesce(p_input->>'status',v.status) not in ('open','paused','closed') or coalesce(p_input->>'priority',v.priority) not in ('low','normal','high','urgent') then raise exception 'Estado no válido'; end if;
 if target is distinct from v.handoff_status then
 -- Never replay replies generated before a change of operator.
 update public.outbound_dispatches set status='cancelled',error_message='Cambio de control desde el CRM' where conversation_id=p_id and status='pending';
 get diagnostics cancelled=row_count;
 select count(*) into processing from public.outbound_dispatches where conversation_id=p_id and status='processing';
 if target in ('human','pending_human') then
 update public.follow_ups set status='cancelled' where conversation_id=p_id and status='pending';
 end if;
 -- Keep the messages in history, but invalidate outstanding AI batches.
 update public.inbound_message_buffer set status='processed',processed_at=now(),last_error='Cambio de control desde el CRM' where conversation_id=p_id and status in ('pending','claimed');
 insert into public.contact_events(contact_id,event_type,source,metadata) values(v.contact_id,'conversation_control_changed','crm',jsonb_build_object('conversation_id',p_id,'from',v.handoff_status,'to',target,'cancelled_dispatches',cancelled,'in_flight',processing));
 end if;
 update public.conversations set handoff_status=target,status=coalesce(p_input->>'status',status),priority=coalesce(p_input->>'priority',priority),internal_notes=case when p_input ? 'internal_notes' then left(p_input->>'internal_notes',10000) else internal_notes end,updated_at=clock_timestamp() where id=p_id returning * into v;
 return jsonb_build_object('conversation',to_jsonb(v),'cancelled_dispatches',cancelled,'in_flight',processing);
end;$$;

create index if not exists olivia_conversation_activity_idx on public.conversations(updated_at desc,id desc);
create index if not exists olivia_message_history_idx on public.messages(conversation_id,created_at desc,id desc);
revoke all on function public.olivia_contact_detail(uuid),public.olivia_conversation_directory(integer,text,text,text),public.olivia_conversation_detail(uuid,uuid),public.olivia_save_conversation(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.olivia_contact_detail(uuid),public.olivia_conversation_directory(integer,text,text,text),public.olivia_conversation_detail(uuid,uuid),public.olivia_save_conversation(uuid,jsonb) to service_role;
