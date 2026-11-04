begin;
do $$
declare cid uuid; vid uuid; bid uuid; batch jsonb; r jsonb; ctx jsonb; p jsonb; product uuid; stamp timestamptz;
begin
 insert into public.contacts(phone,source,preferences) values('+34999000104','qa_test','{"olivia":{"pending_question":"¿Quieres que te apunte al acceso anticipado y te avisemos por WhatsApp?"}}') returning id into cid;
 insert into public.conversations(contact_id,channel) values(cid,'whatsapp') returning id into vid;
 insert into public.inbound_message_buffer(contact_id,conversation_id,channel,external_message_id,status,normalized_text)
 values(cid,vid,'whatsapp','attribute-qa-'||gen_random_uuid(),'claimed','Me llamo Marta. Me gusta el colágeno. No quiero canela. Lo compraré el mes que viene. Sí, apúntame.') returning id into bid;
 batch:=jsonb_build_array(bid);
 r:=public.olivia_agent_tool(cid,vid,batch,'save_name','{"name":"Marta","evidence":"Me llamo Marta"}');
 if r->>'saved'<>'true' or (select first_name from public.contacts where id=cid)<>'Marta' then raise exception 'save_name failed'; end if;
 r:=public.olivia_agent_tool(cid,vid,batch,'save_atributos','[{"attribute_key":"preferred_products","value_jsonb":["Colágeno"],"evidence":"Me gusta el colágeno","update_mode":"merge"},{"attribute_key":"avoided_flavors","value_jsonb":["canela"],"evidence":"No quiero canela","update_mode":"merge"},{"attribute_key":"buying_horizon","value_jsonb":"El mes que viene","evidence":"Lo compraré el mes que viene","update_mode":"replace"}]');
 if r->>'saved'<>'true' or public.olivia_get_attributes(cid)#>>'{preferred_products,0}'<>'Colágeno' or public.olivia_get_attributes(cid)->>'buying_horizon'<>'El mes que viene' then raise exception 'save_atributos failed'; end if;
 perform public.olivia_agent_tool(cid,vid,batch,'save_atributos','[{"attribute_key":"city","value_jsonb":"Madrid","evidence":"Vivo en Madrid"}]');
 if public.olivia_get_attributes(cid) ? 'city' then raise exception 'invented evidence accepted'; end if;
 perform public.olivia_record_attribute(cid,'preferred_products','["Café verde"]','Me gusta el café','llm','merge');
 if jsonb_array_length(public.olivia_get_attributes(cid)->'preferred_products')<>2 then raise exception 'array merge lost existing values'; end if;
 perform public.olivia_save_attribute_crm(cid,'buying_horizon','"Navidad"');
 perform public.olivia_agent_tool(cid,vid,batch,'save_atributos','[{"attribute_key":"buying_horizon","value_jsonb":"El mes que viene","evidence":"Lo compraré el mes que viene"}]');
 if public.olivia_get_attributes(cid)->>'buying_horizon'<>'Navidad' then raise exception 'manual attribute overwritten'; end if;
 r:=public.olivia_agent_tool(cid,vid,batch,'save_tags','[{"tag":"bf2026_early_access","action":"add","evidence":"Sí, apúntame"},{"tag":"interes_colageno","action":"add","evidence":"Me gusta el colágeno"}]');
 if r->>'registered'<>'true' or not exists(select 1 from public.contacts where id=cid and manual_tags @> array['bf2026_early_access','interes_colageno']) then raise exception 'save_tags failed'; end if;
 if exists(select 1 from public.olivia_integration_jobs where contact_id=cid and kind='whatsapp_welcome' and status<>'cancelled') then raise exception 'duplicate template welcome'; end if;
 r:=public.olivia_agent_tool(cid,vid,batch,'save_tags','[{"tag":"bf2026_early_access","action":"add","evidence":"Sí, apúntame"},{"tag":"interes_colageno","action":"add","evidence":"Me gusta el colágeno"}]');
 if r->>'duplicate'<>'true' then raise exception 'tool retry not idempotent'; end if;
 p:=jsonb_build_object('contact_id',cid,'conversation_id',vid,'batch_ids',batch,'batch_text','Me gusta el colágeno','decision','{"intent":"product","suggested_stage":"qualified","lead_score":48,"score_reason":"Interés explícito en colágeno, compra aplazada","temperature":"warm","summary":"Marta prefiere colágeno y evita canela","early_access_action":"already_registered","commercial_updates":[]}'::jsonb);
 ctx:=public.olivia_response_context_b64(public.olivia_conversation_actions_b64(encode(convert_to(p::text,'utf8'),'base64')));
 if ctx#>>'{contact,first_name}'<>'Marta' or ctx#>>'{attributes,avoided_flavors,0}'<>'canela' or ctx#>>'{lead_state,lead_score}'<>'48' or ctx#>>'{score,value}'<>'48' then raise exception 'fresh context/state/score failed'; end if;
 if ctx#>>'{decision,action_result,registered}'<>'true' or ctx#>>'{decision,pending_question}' not ilike '%email%' then raise exception 'tool signup writer welcome failed'; end if;
 if (public.olivia_commercial_profile(cid)->>'tastes') not ilike '%Colágeno%' or (public.olivia_commercial_profile(cid)->>'objections') not ilike '%canela%' then raise exception 'visible profile projection failed'; end if;
 select updated_at into stamp from public.contacts where id=cid;
 perform public.olivia_save_contact(cid,jsonb_build_object('first_name','Marta CRM','expected_updated_at',stamp,'commercial','{"score_override":76}'::jsonb));
 if public.olivia_contact_score(cid)->>'value'<>'76' or (select first_name from public.contacts where id=cid)<>'Marta CRM' then raise exception 'CRM name/manual score failed'; end if;
 -- No acceptance in another batch => no early-access tag.
 update public.contacts set manual_tags='{}',preferences='{}' where id=cid;
 insert into public.inbound_message_buffer(contact_id,conversation_id,channel,external_message_id,status,normalized_text) values(cid,vid,'whatsapp','attribute-ambiguous-'||gen_random_uuid(),'claimed','Sí, me gusta el colágeno') returning id into bid;
 r:=public.olivia_agent_tool(cid,vid,jsonb_build_array(bid),'save_tags','[{"tag":"bf2026_early_access","action":"add","evidence":"Sí, me gusta el colágeno"}]');
 if r->>'registered'='true' or exists(select 1 from public.contacts where id=cid and 'bf2026_early_access'=any(manual_tags)) then raise exception 'ambiguous yes registered'; end if;
 -- Human/opt-out guards prevent profile changes.
 update public.conversations set handoff_status='human' where id=vid;
 r:=public.olivia_agent_tool(cid,vid,jsonb_build_array(bid),'save_name','{"name":"Colágeno","evidence":"colágeno"}');
 if r->>'saved'='true' then raise exception 'human control ignored'; end if;
 if has_function_privilege('authenticated','public.olivia_agent_tool(uuid,uuid,jsonb,text,jsonb)','execute') then raise exception 'agent tool exposed'; end if;
end;$$;
select 'PASS: native memory tools, typed attributes, array merge, manual protection, tag consent, retries, name, fresh context, persisted phase/score and human guard' as result;
rollback;
