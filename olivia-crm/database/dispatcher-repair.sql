create or replace function public.olivia_dispatcher_repair_disclosures() returns integer language plpgsql set search_path='' as $$
declare d public.outbound_dispatches;notice uuid;n integer:=0;
begin
 for d in select od.* from public.outbound_dispatches od join public.outbound_dispatches dep on dep.id::text=od.payload->>'ai_disclosure_dispatch_id'
 join public.contacts c on c.id=od.contact_id
 where od.status='pending' and dep.status='cancelled' and not c.ai_disclosure_shown and od.payload->>'prompt_version'='bf26-v2' order by od.created_at,od.id for update of od skip locked loop
  notice:=public.olivia_ensure_ai_disclosure(d.contact_id,d.conversation_id,d.payload,d.created_at,d.message_id,d.id);
  if notice is not null then update public.outbound_dispatches set payload=payload||jsonb_build_object('ai_disclosure_dispatch_id',notice) where id=d.id;n:=n+1;end if;
 end loop;
 return n;
end;$$;
revoke all on function public.olivia_dispatcher_repair_disclosures() from public,anon,authenticated;
grant execute on function public.olivia_dispatcher_repair_disclosures() to service_role;
