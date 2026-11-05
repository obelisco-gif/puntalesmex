create or replace function public.olivia_ingest_meta_sheet_b64(p_payload_b64 text) returns jsonb language plpgsql set search_path='' as $$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb;cfg jsonb;allowed boolean:=false;fid text:=nullif(p->>'form_id','');r jsonb;
begin
 select value into cfg from public.olivia_config where key='meta_ea26_form' for update;
 if cfg->>'sheet_id'=p->>'source_sheet_id' and cfg->>'tab'=p->>'source_tab'
 and lower(regexp_replace(btrim(p->>'form_name'),'\s+',' ','g'))=lower(cfg->>'form_name')
 and fid is not null and coalesce((cfg->>'approved')::boolean,false) then
  if nullif(cfg->>'form_id','') is null then
   cfg:=cfg||jsonb_build_object('form_id',fid,'bound_at',clock_timestamp());
   update public.olivia_config set value=cfg where key='meta_ea26_form';
  end if;
  allowed:=cfg->>'form_id'=fid;
 end if;
 p:=p||jsonb_build_object('consent_email',allowed and nullif(p->>'email','') is not null and coalesce((cfg->>'consent_email')::boolean,false),
 'consent_whatsapp',allowed and nullif(p->>'phone','') is not null and coalesce((cfg->>'consent_whatsapp')::boolean,false),
 'consent_text',case when allowed then cfg->>'consent_evidence' else null end,'privacy_accepted',false,
 'consent_evidence_source',case when allowed then 'owner_confirmed_form_policy' else 'not_configured' end);
 r:=public.olivia_ingest_lead_b64(encode(convert_to(p::text,'utf8'),'base64'));
 return r||jsonb_build_object('form_policy_matched',allowed,'consent_email',p->'consent_email','consent_whatsapp',p->'consent_whatsapp');
end;$$;
revoke all on function public.olivia_ingest_meta_sheet_b64(text) from public,anon,authenticated;
grant execute on function public.olivia_ingest_meta_sheet_b64(text) to service_role;
insert into public.olivia_config(key,value) values('meta_ea26_form',jsonb_build_object(
 'sheet_id','11LxXyAzPdGBv5SOBt0gojUCRSiUQAXq6BCdE1scnkTs','tab','Hoja 1','form_name','early access 26','form_id',null,
 'approved',true,'consent_email',true,'consent_whatsapp',true,'confirmed_at','2026-11-05',
 'consent_evidence','Confirmación del responsable el 05/11/2026: las personas que llegan del formulario Meta early access 26 han otorgado consentimiento para email y WhatsApp. Evidencia administrativa; no es una transcripción del texto del formulario.'
)) on conflict(key) do nothing;
