-- All fixtures and config changes roll back. No external calls or messages.
begin;
do $$
declare r jsonb; p jsonb; cid uuid; vid uuid; bid uuid; product uuid; email_only uuid; phone_only uuid; both_id uuid; payload text; result jsonb; n int; saved_stamp timestamptz;
begin
 r:=public.olivia_ingest_lead_b64(encode(convert_to('{"external_lead_id":"qa-single-email-20261104","email":"single-email-20261104@example.invalid","consent_email":true,"consent_text":"Avisos de Early Access por email"}','utf8'),'base64'));
 email_only:=(r->>'contact_id')::uuid;
 if not exists(select 1 from public.contacts where id=email_only and phone is null) or exists(select 1 from public.olivia_integration_jobs where contact_id=email_only and kind='whatsapp_welcome') then raise exception 'email-only routing failed'; end if;
 r:=public.olivia_ingest_lead_b64(encode(convert_to('{"external_lead_id":"qa-single-phone-20261104","phone":"+34999000101","consent_whatsapp":true,"consent_text":"Avisos de Early Access por WhatsApp"}','utf8'),'base64'));
 phone_only:=(r->>'contact_id')::uuid;
 if not exists(select 1 from public.contacts where id=phone_only and email is null) or not exists(select 1 from public.olivia_integration_jobs where contact_id=phone_only and kind='whatsapp_welcome') then raise exception 'phone-only routing failed'; end if;
 r:=public.olivia_ingest_lead_b64(encode(convert_to('{"external_lead_id":"qa-both-20261104","email":"both-20261104@example.invalid","phone":"+34999000102","consent_whatsapp":true,"consent_email":true,"consent_text":"Avisos por ambos canales"}','utf8'),'base64'));
 both_id:=(r->>'contact_id')::uuid;
 if (select count(*) from public.olivia_integration_jobs where contact_id=both_id)<>2 then raise exception 'both routing failed'; end if;
 r:=public.olivia_ingest_lead_b64(encode(convert_to('{"external_lead_id":"qa-both-20261104","email":"both-20261104@example.invalid"}','utf8'),'base64'));
 if r->>'duplicate'<>'true' then raise exception 'form retry not idempotent'; end if;
 -- Exercise claim logic inside this transaction; no workflow is executed.
 update public.olivia_config set value=value||'{"klaviyo_sync_enabled":true}'::jsonb where key='bf2026';
 -- Older real jobs must not be claimed even temporarily in this test.
 update public.olivia_integration_jobs set available_at=now()+interval '1 day' where contact_id not in (email_only,phone_only,both_id);
 perform public.olivia_claim_integration('klaviyo_early_access');
 perform public.olivia_claim_integration('klaviyo_early_access');
 perform public.olivia_claim_integration('klaviyo_early_access');
 if not exists(select 1 from public.olivia_integration_jobs where contact_id=phone_only and kind='klaviyo_early_access' and status='waiting_consent') then raise exception 'phone-only attempted email subscription'; end if;
 if (select count(*) from public.olivia_integration_jobs where contact_id in (email_only,both_id) and kind='klaviyo_early_access' and status='processing')<>2 then raise exception 'email consent routing failed'; end if;
 insert into public.contacts(phone,preferences) values('+34999000103','{"olivia":{"pending_question":"¿Quieres que te apunte al acceso anticipado y te avisemos por WhatsApp?","summary":"Conservar memoria"}}') returning id into cid;
 insert into public.conversations(contact_id,channel) values(cid,'whatsapp') returning id into vid;
 insert into public.inbound_message_buffer(contact_id,conversation_id,channel,external_message_id,status,normalized_text) values(cid,vid,'whatsapp','qa-conversation-20261104','claimed','Sí, apúntame') returning id into bid;
 p:=jsonb_build_object('contact_id',cid,'conversation_id',vid,'batch_ids',jsonb_build_array(bid),'batch_text','Sí, apúntame','decision',jsonb_build_object('early_access_action','registration_requested','registration_evidence','Sí, apúntame','opt_out',false,'needs_human',false,'commercial_updates','[]'::jsonb));
 payload:=encode(convert_to(p::text,'utf8'),'base64');
 result:=convert_from(decode(public.olivia_conversation_actions_b64(payload),'base64'),'utf8')::jsonb;
 if result#>>'{decision,action_result,registered}'<>'true' or result#>>'{decision,pending_question}' not ilike '%email%' then raise exception 'conversation registration/welcome failed'; end if;
 if not exists(select 1 from public.contacts where id=cid and 'bf2026_early_access'=any(manual_tags)) or exists(select 1 from public.olivia_integration_jobs where contact_id=cid and kind='whatsapp_welcome' and status<>'cancelled') then raise exception 'conversation tag/template suppression failed'; end if;
 perform public.olivia_conversation_actions_b64(payload);
 if (select count(*) from public.contact_events where contact_id=cid and event_type='conversation_actions')<>1 then raise exception 'conversation retry duplicated actions'; end if;
 -- An offer is never an inscription.
 update public.contacts set manual_tags='{}',preferences='{}' where id=cid;
 update public.inbound_message_buffer set normalized_text='¿Qué es Black Friday?',external_message_id='qa-offer-20261104' where id=bid;
 p:=p||jsonb_build_object('batch_ids',jsonb_build_array(gen_random_uuid()));
 insert into public.inbound_message_buffer(id,contact_id,conversation_id,channel,external_message_id,status,normalized_text) values((p->'batch_ids'->>0)::uuid,cid,vid,'whatsapp','qa-offer2-20261104','claimed','¿Qué es Black Friday?');
 p:=p||jsonb_build_object('decision','{"early_access_action":"offer_registration","commercial_updates":[],"registration_evidence":""}'::jsonb);
 perform public.olivia_conversation_actions_b64(encode(convert_to(p::text,'utf8'),'base64'));
 if exists(select 1 from public.contacts where id=cid and 'bf2026_early_access'=any(manual_tags)) then raise exception 'offer enrolled without consent'; end if;
 -- Email capture after the explicit offer; context must reload for writer.
 update public.contacts set manual_tags=array['bf2026_early_access'],preferences='{"olivia":{"pending_question":"¿Quieres que también te avisemos por email? Si te interesa, dime tu correo.","summary":"Conservar memoria"}}' where id=cid;
 p:=p||jsonb_build_object('batch_ids',jsonb_build_array(gen_random_uuid()),'batch_text','Mi email es conversation-20261104@example.invalid','decision','{"early_access_action":"already_registered","captured_email":"conversation-20261104@example.invalid","email_opt_in":true,"commercial_updates":[]}'::jsonb);
 insert into public.inbound_message_buffer(id,contact_id,conversation_id,channel,external_message_id,status,normalized_text) values((p->'batch_ids'->>0)::uuid,cid,vid,'whatsapp','qa-email-20261104','claimed',p->>'batch_text');
 result:=public.olivia_response_context_b64(public.olivia_conversation_actions_b64(encode(convert_to(p::text,'utf8'),'base64')));
 if result#>>'{contact,email}'<>'conversation-20261104@example.invalid' or result#>>'{decision,action_result,email_opt_in_recorded}'<>'true' then raise exception 'email save/consent/context failed'; end if;
 -- Editable profile merge preserves the agent memory, and stale edits fail.
 select updated_at into saved_stamp from public.contacts where id=cid;
 perform public.olivia_save_contact(cid,jsonb_build_object('expected_updated_at',saved_stamp,'stage','qualified','commercial','{"tastes":"Canela","objections":"Prefiere sin jengibre","score_override":72}'::jsonb));
 if (select preferences#>>'{olivia,summary}' from public.contacts where id=cid)<>'Conservar memoria' or (public.olivia_contact_score(cid)->>'value')::int<>72 then raise exception 'profile merge/score failed'; end if;
 begin
  perform public.olivia_save_contact(cid,jsonb_build_object('expected_updated_at',saved_stamp,'commercial','{}'::jsonb));
  raise exception 'stale edit accepted';
 exception when others then if sqlerrm='stale edit accepted' then raise; end if; end;
 select id into product from public.catalog_products where status='publish' limit 1;
 perform public.olivia_save_commercial_entry(cid,jsonb_build_object('kind','purchase','product_id',product,'reference','QA-PURCHASE-1','details','Pedido verificado por el equipo','status','confirmed','amount',39.90,'quantity',2));
 perform public.olivia_save_commercial_entry(cid,jsonb_build_object('kind','purchase','reference','QA-PURCHASE-1','details','Pedido actualizado','status','confirmed','amount',40));
 if (select count(*) from public.contact_commercial_entries where contact_id=cid and kind='purchase')<>1 or (select stage from public.contacts where id=cid)<>'customer' then raise exception 'purchase upsert/stage failed'; end if;
 result:=public.olivia_context_v2_b64(encode(convert_to(p::text,'utf8'),'base64'));
 if jsonb_array_length(result->'commercial_entries')<>1 or result#>>'{commercial_profile,tastes}'<>'Canela' or result#>>'{score,value}'<>'72' then raise exception 'agent commercial context missing'; end if;
 perform public.olivia_apply_optout(cid,'whatsapp','STOP');
 if not exists(select 1 from public.contact_channel_consents where contact_id=cid and channel='whatsapp' and status='revoked') then raise exception 'STOP failed'; end if;
end;$$;
select 'PASS: single-channel forms, consent routing, deduplication, conversational signup, email capture, memory merge, score, purchases, context and STOP' as result;
rollback;
