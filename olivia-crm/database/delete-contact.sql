create table if not exists public.olivia_contact_deletions(
 id uuid primary key default gen_random_uuid(),contact_id uuid not null,actor_id uuid not null,
 deleted_at timestamptz not null default clock_timestamp(),counts jsonb not null
);
alter table public.olivia_contact_deletions enable row level security;
revoke all on public.olivia_contact_deletions from public,anon,authenticated;
grant all on public.olivia_contact_deletions to service_role;

create or replace function public.olivia_delete_contact(p_id uuid,p_expected_updated_at timestamptz,p_actor uuid) returns jsonb language plpgsql set search_path='' as $$
declare c public.contacts;chats uuid[];handoffs uuid[];counts jsonb;n integer;
begin
 if p_actor is null or p_expected_updated_at is null then raise exception 'Confirmación de administrador requerida';end if;
 select * into c from public.contacts where id=p_id for update;
 if not found then return jsonb_build_object('deleted',true,'already_deleted',true);end if;
 if c.updated_at is distinct from p_expected_updated_at then raise exception 'El contacto ha cambiado. Actualiza la ficha antes de eliminar.';end if;
 chats:=array(select id from public.conversations where contact_id=p_id);
 perform 1 from public.olivia_handoffs where contact_id=p_id or conversation_id=any(chats) order by id for update;
 handoffs:=array(select id from public.olivia_handoffs where contact_id=p_id or conversation_id=any(chats));
 perform 1 from public.outbound_dispatches where contact_id=p_id or conversation_id=any(chats) or payload->>'handoff_id'=any(array(select unnest(handoffs)::text)) order by id for update;
 perform 1 from public.olivia_integration_jobs where contact_id=p_id order by id for update;
 if exists(select 1 from public.outbound_dispatches where (contact_id=p_id or conversation_id=any(chats) or payload->>'handoff_id'=any(array(select unnest(handoffs)::text))) and status='processing')
 or exists(select 1 from public.olivia_integration_jobs where contact_id=p_id and status='processing') then
  raise exception 'Hay envíos o integraciones en curso. Espera a que terminen antes de eliminar.';
 end if;
 counts:=jsonb_build_object('conversations',cardinality(chats),'messages',(select count(*) from public.messages where conversation_id=any(chats)));
 delete from public.outbound_dispatches where contact_id=p_id or conversation_id=any(chats) or payload->>'handoff_id'=any(array(select unnest(handoffs)::text));
 get diagnostics n=row_count;counts:=counts||jsonb_build_object('dispatches',n);
 delete from public.olivia_integration_jobs where contact_id=p_id;
 get diagnostics n=row_count;counts:=counts||jsonb_build_object('integration_jobs',n);
 delete from public.olivia_handoffs where id=any(handoffs);
 delete from public.inbound_message_buffer where contact_id=p_id or conversation_id=any(chats);
 delete from public.agent_runs where contact_id=p_id or conversation_id=any(chats);
 delete from public.follow_ups where contact_id=p_id or conversation_id=any(chats);
 delete from public.messages where conversation_id=any(chats);
 delete from public.conversations where contact_id=p_id;
 delete from public.contact_channel_consents where contact_id=p_id;
 delete from public.lead_attributes where contact_id=p_id;
 delete from public.lead_states where contact_id=p_id;
 delete from public.contact_commercial_entries where contact_id=p_id;
 delete from public.contact_events where contact_id=p_id;
 delete from public.attribution_touchpoints where contact_id=p_id;
 delete from public.lead_magnet_deliveries where contact_id=p_id;
 delete from public.product_recommendations where contact_id=p_id;
 update public.woo_orders set contact_id=null,match_status='unmatched',matched_by=null where contact_id=p_id;
 delete from public.contacts where id=p_id;
 insert into public.olivia_contact_deletions(contact_id,actor_id,counts) values(p_id,p_actor,counts);
 return jsonb_build_object('deleted',true,'counts',counts);
end;$$;
revoke all on function public.olivia_delete_contact(uuid,timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.olivia_delete_contact(uuid,timestamptz,uuid) to service_role;
