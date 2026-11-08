begin;
do $$
declare p jsonb;r jsonb;c uuid;
begin
 p:=jsonb_build_object('external_lead_id','sheet-policy-first','form_id','111','form_name','early access 26','source_sheet_id','11LxXyAzPdGBv5SOBt0gojUCRSiUQAXq6BCdE1scnkTs','source_tab','Hoja 1','email','sheet-policy@example.invalid','phone','+34999000881','first_name','Prueba ficticia','submitted_at',clock_timestamp());
 r:=public.olivia_ingest_meta_sheet_b64(encode(convert_to(p::text,'utf8'),'base64'));c:=(r->>'contact_id')::uuid;
 if not (r->>'form_policy_matched')::boolean or not (r->>'consent_email')::boolean or not (r->>'consent_whatsapp')::boolean then raise exception 'Both-channel policy not applied';end if;
 if (select value->>'form_id' from public.olivia_config where key='meta_ea26_form')<>'111' then raise exception 'Form identity not pinned';end if;
 if (select count(*) from public.contact_channel_consents where contact_id=c and status='granted')<>2 then raise exception 'Permissions not stored';end if;
 r:=public.olivia_ingest_meta_sheet_b64(encode(convert_to(p::text,'utf8'),'base64'));
 if not (r->>'duplicate')::boolean then raise exception 'Duplicate row created another contact';end if;
 p:=p||jsonb_build_object('external_lead_id','sheet-policy-partial','form_id','222','email','sheet-partial@example.invalid','phone',null);
 r:=public.olivia_ingest_meta_sheet_b64(encode(convert_to(p::text,'utf8'),'base64'));
 if (r->>'form_policy_matched')::boolean or (r->>'consent_email')::boolean then raise exception 'Another form inherited permissions';end if;
 p:=p||jsonb_build_object('external_lead_id','sheet-policy-email','form_id','111','email','sheet-email@example.invalid');
 r:=public.olivia_ingest_meta_sheet_b64(encode(convert_to(p::text,'utf8'),'base64'));
 if not (r->>'consent_email')::boolean or (r->>'consent_whatsapp')::boolean then raise exception 'Email-only lead routed incorrectly';end if;
 p:=p||jsonb_build_object('external_lead_id','sheet-policy-whatsapp','email',null,'phone','+34999000882');
 r:=public.olivia_ingest_meta_sheet_b64(encode(convert_to(p::text,'utf8'),'base64'));
 if (r->>'consent_email')::boolean or not (r->>'consent_whatsapp')::boolean then raise exception 'WhatsApp-only lead routed incorrectly';end if;
end;$$;
rollback;
select 'PASS: consent confirmed for exact source/form, form ID pinning, duplicate protection, no permission inheritance and email/WhatsApp-only routing.' as result;
