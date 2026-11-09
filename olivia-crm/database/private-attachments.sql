create table if not exists public.olivia_message_attachments (
 message_id uuid primary key references public.messages(id) on delete cascade,
 media_type text not null check (media_type in ('image','sticker','audio','video','document')),
 mime_type text not null,
 data bytea not null check (octet_length(data) > 0 and octet_length(data) <= 20971520),
 created_at timestamptz not null default now()
);
alter table public.olivia_message_attachments enable row level security;
revoke all on public.olivia_message_attachments from public, anon, authenticated;
grant select,insert,update,delete on public.olivia_message_attachments to service_role;
create or replace function public.olivia_save_message_attachment(p_external_message_id text,p_media_id text,p_mime_type text,p_data_base64 text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m_id uuid; m_type text; bytes bytea;
begin
 if length(coalesce(p_data_base64,''))>27962028 then raise exception 'Adjunto demasiado grande'; end if;
 select m.id,b.message_type into m_id,m_type from public.messages m join public.inbound_message_buffer b on b.external_message_id=m.external_message_id and b.conversation_id=m.conversation_id
 where m.direction='inbound' and m.external_message_id=p_external_message_id and b.message_type in ('image','sticker','audio','video','document')
 and exists(select 1 from jsonb_array_elements(b.media) item where item->>'id'=p_media_id) limit 1;
 if m_id is null then raise exception 'Adjunto sin mensaje asociado'; end if;
 if coalesce(p_mime_type,'') !~ '^(image/(jpeg|png|webp|gif)|audio/(ogg|mpeg|mp4|aac|amr)|video/(mp4|3gpp)|application/(pdf|msword|vnd[.]ms-excel|vnd[.]openxmlformats-officedocument[.]wordprocessingml[.]document|vnd[.]openxmlformats-officedocument[.]spreadsheetml[.]sheet)|text/plain)$' then raise exception 'Tipo de archivo no admitido'; end if;
 bytes:=decode(p_data_base64,'base64');
 insert into public.olivia_message_attachments(message_id,media_type,mime_type,data) values(m_id,m_type,p_mime_type,bytes)
 on conflict(message_id) do nothing;
 return jsonb_build_object('saved',true,'message_id',m_id);
end $$;
revoke all on function public.olivia_save_message_attachment(text,text,text,text) from public,anon,authenticated;
grant execute on function public.olivia_save_message_attachment(text,text,text,text) to service_role;
create or replace function public.olivia_read_message_attachment(p_conversation_id uuid,p_message_id uuid)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('type',a.media_type,'mime_type',a.mime_type,'data',encode(a.data,'base64'))
 from public.olivia_message_attachments a join public.messages m on m.id=a.message_id
 join public.conversations v on v.id=m.conversation_id join public.contacts c on c.id=v.contact_id
 where m.id=p_message_id and m.conversation_id=p_conversation_id and coalesce(c.source,'')<>'qa_test'
$$;
revoke all on function public.olivia_read_message_attachment(uuid,uuid) from public,anon,authenticated;
grant execute on function public.olivia_read_message_attachment(uuid,uuid) to service_role;
CREATE OR REPLACE FUNCTION public.olivia_conversation_detail(p_id uuid, p_before uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v public.conversations; items jsonb; older boolean; cursor_time timestamptz; oldest_id uuid; oldest_time timestamptz;
begin
 select cv.* into v from public.conversations cv join public.contacts c on c.id=cv.contact_id where cv.id=p_id and coalesce(c.source,'')<>'qa_test';
 if not found then return null; end if;
 if p_before is not null then
 select created_at into cursor_time from public.messages where id=p_before and conversation_id=p_id;
 if not found then raise exception 'Cursor no válido'; end if;
 end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at,r.id),'[]') into items from (
 select m.*, (select a.media_type from public.olivia_message_attachments a where a.message_id=m.id) as attachment_type, (select b.message_type from public.inbound_message_buffer b where b.external_message_id=m.external_message_id and b.conversation_id=m.conversation_id and b.message_type in ('image','sticker','audio','video','document') limit 1) as incoming_media_type, (select d.payload->>'sender_role' from public.outbound_dispatches d where d.message_id=m.id order by d.created_at desc,d.id desc limit 1) as sender_role, (select d.status from public.outbound_dispatches d where d.message_id=m.id order by d.created_at desc,d.id desc limit 1) as delivery_status
 from public.messages m where m.conversation_id=p_id and (p_before is null or (m.created_at,m.id)<(cursor_time,p_before))
 order by m.created_at desc,m.id desc limit 50)r;
 oldest_id:=(items->0->>'id')::uuid; oldest_time:=(items->0->>'created_at')::timestamptz;
 select exists(select 1 from public.messages where conversation_id=p_id and (created_at,id)<(oldest_time,oldest_id)) into older;
 return jsonb_build_object('conversation',to_jsonb(v),'contact',public.olivia_contact_detail(v.contact_id),'messages',items,'has_older',older,
 'outbound_enabled',coalesce((select (value->>'whatsapp_outbound_enabled')::boolean from public.olivia_config where key='bf2026'),false),
 'message_count',(select count(*) from public.messages where conversation_id=p_id),
 'channel_consents',coalesce((select jsonb_agg(jsonb_build_object('channel',channel,'status',status)) from public.contact_channel_consents where contact_id=v.contact_id),'[]'));
end;$function$
;
create table if not exists public.olivia_attachment_attempts (
 message_id uuid primary key references public.messages(id) on delete cascade,
 attempts integer not null default 0,
 last_attempt_at timestamptz not null default now()
);
alter table public.olivia_attachment_attempts enable row level security;
revoke all on public.olivia_attachment_attempts from public,anon,authenticated;
grant select,insert,update,delete on public.olivia_attachment_attempts to service_role;
create or replace function public.olivia_claim_attachment()
returns table(external_message_id text,media_id text,mime_type text)
language sql security definer set search_path='' as $$
 with candidate as (
  select m.id,m.external_message_id,b.media->0->>'id' media_id,split_part(b.media->0->>'mime_type',';',1) mime_type
  from public.inbound_message_buffer b join public.messages m on m.external_message_id=b.external_message_id and m.conversation_id=b.conversation_id
  left join public.olivia_message_attachments a on a.message_id=m.id
  left join public.olivia_attachment_attempts t on t.message_id=m.id
  where m.direction='inbound' and b.message_type in ('image','sticker','audio','video','document')
  and b.received_at > now()-interval '29 days' and a.message_id is null
  and b.media->0->>'id' ~ '^[0-9]+$'
  and split_part(b.media->0->>'mime_type',';',1) ~ '^(image/(jpeg|png|webp|gif)|audio/(ogg|mpeg|mp4|aac|amr)|video/(mp4|3gpp)|application/(pdf|msword|vnd[.]ms-excel|vnd[.]openxmlformats-officedocument[.]wordprocessingml[.]document|vnd[.]openxmlformats-officedocument[.]spreadsheetml[.]sheet)|text/plain)$'
  and coalesce(t.attempts,0)<5 and (t.last_attempt_at is null or t.last_attempt_at<now()-interval '5 minutes')
  order by coalesce(t.last_attempt_at,'-infinity'::timestamptz),b.received_at desc limit 1
 ), claimed as (
  insert into public.olivia_attachment_attempts(message_id,attempts,last_attempt_at)
  select id,1,now() from candidate on conflict(message_id) do update set attempts=public.olivia_attachment_attempts.attempts+1,last_attempt_at=now()
  returning message_id
 )
 select candidate.external_message_id,candidate.media_id,candidate.mime_type from candidate join claimed on claimed.message_id=candidate.id
$$;
revoke all on function public.olivia_claim_attachment() from public,anon,authenticated;
grant execute on function public.olivia_claim_attachment() to service_role;
