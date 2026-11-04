begin;
do $$
declare c uuid; v uuid; m uuid; cursor_id uuid; d jsonb; stamp timestamptz; n integer;
begin
 insert into public.contacts(email,source,first_name) values('workspace@example.invalid','crm','Workspace fixture') returning id into c;
 insert into public.conversations(contact_id,channel) values(c,'whatsapp') returning id into v;
 -- Identical timestamps exercise the UUID tie-breaker across message pages.
 insert into public.messages(conversation_id,direction,body,created_at) select v,'inbound','Message '||i,'2026-11-04T10:00:00Z'::timestamptz from generate_series(1,123)i;
 d:=public.olivia_conversation_detail(v,null);
 if jsonb_array_length(d->'messages')<>50 or not (d->>'has_older')::boolean or (d->>'message_count')::integer<>123 then raise exception 'Latest message page incorrect'; end if;
 cursor_id:=(d->'messages'->0->>'id')::uuid;
 d:=public.olivia_conversation_detail(v,cursor_id);
 if jsonb_array_length(d->'messages')<>50 or not (d->>'has_older')::boolean then raise exception 'Second message page incorrect'; end if;
 cursor_id:=(d->'messages'->0->>'id')::uuid;
 d:=public.olivia_conversation_detail(v,cursor_id);
 if jsonb_array_length(d->'messages')<>23 or (d->>'has_older')::boolean then raise exception 'Oldest message page incorrect'; end if;
 if d->'contact'->>'id'<>c::text then raise exception 'Wrong contact context'; end if;
 insert into public.conversations(contact_id,channel,updated_at) select c,'email',now()+i*interval '1 second' from generate_series(1,61)i;
 d:=public.olivia_conversation_directory(1,'Workspace fixture','','');
 if (d->>'total')::integer<>62 or jsonb_array_length(d->'rows')<>50 then raise exception 'Directory first page incorrect'; end if;
 d:=public.olivia_conversation_directory(99,'Workspace fixture','','');
 if (d->>'page')::integer<>2 or jsonb_array_length(d->'rows')<>12 then raise exception 'Directory page clamp incorrect'; end if;
 insert into public.outbound_dispatches(contact_id,conversation_id,channel,status) values(c,v,'whatsapp','pending');
 insert into public.inbound_message_buffer(contact_id,conversation_id,status) values(c,v,'claimed');
 insert into public.follow_ups(contact_id,conversation_id,channel,status) values(c,v,'whatsapp','pending');
 select updated_at into stamp from public.conversations where id=v;
 d:=public.olivia_save_conversation(v,jsonb_build_object('handoff_status','human','expected_updated_at',stamp));
 if d->'conversation'->>'handoff_status'<>'human' or (d->>'cancelled_dispatches')::integer<>1 then raise exception 'Takeover incorrect'; end if;
 if exists(select 1 from public.outbound_dispatches where conversation_id=v and status='pending') or exists(select 1 from public.inbound_message_buffer where conversation_id=v and status='claimed') or exists(select 1 from public.follow_ups where conversation_id=v and status='pending') then raise exception 'Automation not paused'; end if;
 begin
 perform public.olivia_save_conversation(v,jsonb_build_object('handoff_status','bot','expected_updated_at',stamp));
 raise exception 'Stale save accepted';
 exception when others then if sqlerrm not like '%conversación ha cambiado%' then raise; end if; end;
 select updated_at into stamp from public.conversations where id=v;
 d:=public.olivia_save_conversation(v,jsonb_build_object('handoff_status','bot','expected_updated_at',stamp));
 if d->'conversation'->>'handoff_status'<>'bot' then raise exception 'Return control failed'; end if;
 select count(*) into n from public.messages where conversation_id=v;
 if n<>123 then raise exception 'Control change sent or removed a message'; end if;
 if has_function_privilege('anon','public.olivia_conversation_detail(uuid,uuid)','execute') or has_function_privilege('authenticated','public.olivia_save_conversation(uuid,jsonb)','execute') then raise exception 'Public RPC exposure'; end if;
end;$$;
select 'PASS: directory pagination, complete message history, contact context, takeover cancellation, stale-write protection and return without sending.' as result;
rollback;
