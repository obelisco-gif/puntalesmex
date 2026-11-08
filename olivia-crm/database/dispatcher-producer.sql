CREATE OR REPLACE FUNCTION public.olivia_complete_v2_b64(p_payload_b64 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 perform public.olivia_store_lead_state(cid,d);
 insert into public.agent_runs(conversation_id,contact_id,inbound_batch_ids,agent_role,status,decision,prompt_version,input_summary,output_summary,completed_at)
 values(vid,cid,batch,'conversation',case when reply='' then 'skipped' else 'completed' end,d,'bf26-v2',left(p->>'batch_text',2000),reply,now());
 if reply<>'' and (opt or not exists(select 1 from public.contact_channel_consents where contact_id=cid and channel='whatsapp' and status='revoked')) then
  insert into public.messages(conversation_id,direction,body) values(vid,'outbound',reply) returning id into mid;
  insert into public.outbound_dispatches(contact_id,conversation_id,message_id,channel,delivery_type,payload,idempotency_key)
  values(cid,vid,mid,'whatsapp','freeform',jsonb_build_object('body',reply,'kind',case when human then 'handoff_acknowledgement' else 'bot_reply' end,'optout_confirmation',opt,'prompt_version','bf26-v2'),key)
  on conflict(idempotency_key) where idempotency_key is not null do nothing returning id into did;
 end if;
 update public.inbound_message_buffer set status='processed',processed_at=now() where id=any(batch) and status='claimed';
 return jsonb_build_object('saved',true,'dispatch_id',did,'opt_out_recorded',opt,'needs_human',human);
end;$function$;
revoke all on function public.olivia_complete_v2_b64(text) from public,anon,authenticated;
grant execute on function public.olivia_complete_v2_b64(text) to service_role;
