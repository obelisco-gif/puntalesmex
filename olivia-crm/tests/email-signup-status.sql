begin;
do $$
declare c uuid;v uuid;r jsonb;j uuid;p jsonb;
begin
 insert into public.contacts(email,phone) values('email-status@example.invalid','+34999000661') returning id into c;
 insert into public.conversations(contact_id,channel) values(c,'whatsapp') returning id into v;
 if public.olivia_email_signup_status(c)->>'status'<>'consent_missing' then raise exception 'Missing consent not reflected';end if;
 insert into public.contact_channel_consents(contact_id,channel,status,source,evidence) values(c,'email','granted','crm','{}');
 insert into public.olivia_integration_jobs(contact_id,kind,campaign,status,idempotency_key) values(c,'klaviyo_early_access','bf2026_early_access','pending','email-status-qa') returning id into j;
 if public.olivia_email_signup_status(c)->>'status'<>'pending' then raise exception 'Consent falsely confirmed membership';end if;
 update public.olivia_integration_jobs set status='blocked',payload='{"block_reason":"hard_bounce","membership_confirmed":false}',last_error='Rebote permanente' where id=j;
 r:=public.olivia_email_signup_status(c);
 if r->>'status'<>'blocked' or r->>'reason_code'<>'hard_bounce' or (r->>'membership_confirmed')::boolean then raise exception 'Blocked state lost';end if;
 p:=jsonb_build_object('contact_id',c,'conversation_id',v,'batch_ids','[]'::jsonb);
 r:=public.olivia_response_context_b64(encode(convert_to(p::text,'utf8'),'base64'));
 if r#>>'{email_signup,status}'<>'blocked' then raise exception 'Writer did not receive blockage';end if;
 update public.olivia_integration_jobs set status='completed',payload='{}' where id=j;
 if public.olivia_email_signup_status(c)->>'status'='confirmed' then raise exception 'Job completion without membership was treated as subscribed';end if;
 update public.olivia_integration_jobs set payload='{"membership_confirmed":true}' where id=j;
 if public.olivia_email_signup_status(c)->>'status'<>'confirmed' then raise exception 'Real confirmation missing';end if;
end;$$;
rollback;
select 'PASS: email permission, pending, hard bounce, actual membership and writer context remain distinct.' as result;
