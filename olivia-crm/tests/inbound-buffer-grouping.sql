begin;
do $t$
declare c uuid;v uuid;n integer;
begin
 insert into public.contacts(email) values('qa-buffer@example.invalid') returning id into c;
 insert into public.conversations(contact_id,channel) values(c,'whatsapp') returning id into v;
 insert into public.inbound_message_buffer(channel,external_message_id,external_thread_id,contact_id,conversation_id,normalized_text,status,received_at,process_after,attempts)
 values('whatsapp','qa-b1','qa-thread',c,v,'Hola','pending',now()-interval '35 seconds',now()-interval '5 seconds',0),
 ('whatsapp','qa-b2','qa-thread',c,v,'Quiero café','pending',now()-interval '15 seconds',now()+interval '15 seconds',0);
 select count(*) into n from public.claim_inbound_message_batch('whatsapp','qa-thread',20);
 if n<>0 then raise exception 'The first timer split a still-active message burst';end if;
 update public.inbound_message_buffer set process_after=now()-interval '1 second' where external_thread_id='qa-thread';
 select count(*) into n from public.claim_inbound_message_batch('whatsapp','qa-thread',20);
 if n<>2 then raise exception 'Expected both messages in one batch, got %',n;end if;
 select count(*) into n from public.claim_inbound_message_batch('whatsapp','qa-thread',20);
 if n<>0 then raise exception 'Duplicate claim';end if;
end;$t$;rollback;
select 'PASS: waits for quiet period and claims consecutive messages as one batch' as result;
