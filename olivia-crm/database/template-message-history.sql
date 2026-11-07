create or replace function public.olivia_record_sent_template()
returns trigger language plpgsql set search_path='' as $fn$
declare m uuid; template_name text; template_body text; args jsonb; i integer; v text;
begin
 if new.status<>'sent' or new.delivery_type<>'template' or new.contact_id is null or new.conversation_id is null or new.message_id is not null then return new;end if;
 template_name:=coalesce(nullif(new.payload->>'template_name',''),'plantilla');
 select case when value->>'whatsapp_template_name'=template_name then nullif(value->>'whatsapp_template_body','') else null end into template_body from public.olivia_config where key='bf2026';
 args:=coalesce(new.payload#>'{template_components,0,parameters}','[]'::jsonb);
 if template_body is not null then
  for i in 0..jsonb_array_length(args)-1 loop
   v:=coalesce(args->i->>'text','');
   template_body:=replace(template_body,'{{'||(i+1)::text||'}}',v);
  end loop;
 else
  template_body:='[Plantilla de WhatsApp «'||template_name||'» enviada. Texto completo no disponible.]';
  if jsonb_array_length(args)>0 then template_body:=template_body||' Datos de la plantilla: '||coalesce((select string_agg(x->>'text',', ' order by ord) from jsonb_array_elements(args) with ordinality t(x,ord) where x->>'text' is not null),''); end if;
 end if;
 insert into public.messages(conversation_id,direction,body,external_message_id,created_at)
 values(new.conversation_id,'outbound',template_body,new.external_dispatch_id,coalesce(new.sent_at,now())) returning id into m;
 update public.outbound_dispatches set message_id=m where id=new.id and message_id is null;
 return new;
end;$fn$;
drop trigger if exists olivia_record_sent_template on public.outbound_dispatches;
create trigger olivia_record_sent_template after insert or update of status on public.outbound_dispatches for each row execute function public.olivia_record_sent_template();
revoke all on function public.olivia_record_sent_template() from public,anon,authenticated;
grant execute on function public.olivia_record_sent_template() to service_role;
