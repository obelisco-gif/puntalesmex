create or replace function public.olivia_contact_directory(p_page integer default 1,p_search text default '',p_stage text default '',p_tag text default '') returns jsonb
language plpgsql set search_path='' as $$
declare total integer; page integer; items jsonb;
begin
 if p_stage not in ('','new','engaged','qualified','recommended','purchase_intent','customer','on_hold','lost','unsubscribed') then raise exception 'Fase no válida'; end if;
 select count(*) into total from public.contacts c where coalesce(c.source,'')<>'qa_test'
 and (p_stage='' or c.stage=p_stage) and (p_tag='' or p_tag=any(c.manual_tags))
 and (coalesce(c.first_name,'') ilike '%'||left(p_search,100)||'%' or coalesce(c.email,'') ilike '%'||left(p_search,100)||'%' or coalesce(c.phone,'') ilike '%'||left(p_search,100)||'%');
 page:=least(greatest(1,coalesce(p_page,1)),greatest(1,ceil(total/50.0)::integer));
 select coalesce(jsonb_agg(to_jsonb(r) order by r.updated_at desc,r.id desc),'[]') into items from (
 select c.id,c.first_name,c.email,c.phone,c.stage,c.source,c.manual_tags,c.updated_at,
 (public.olivia_contact_score(c.id)->>'value')::integer as score,
 (select v.id from public.conversations v where v.contact_id=c.id order by v.updated_at desc,v.id desc limit 1) as conversation_id
 from public.contacts c where coalesce(c.source,'')<>'qa_test'
 and (p_stage='' or c.stage=p_stage) and (p_tag='' or p_tag=any(c.manual_tags))
 and (coalesce(c.first_name,'') ilike '%'||left(p_search,100)||'%' or coalesce(c.email,'') ilike '%'||left(p_search,100)||'%' or coalesce(c.phone,'') ilike '%'||left(p_search,100)||'%')
 order by c.updated_at desc,c.id desc limit 50 offset (page-1)*50)r;
 return jsonb_build_object('rows',items,'total',total,'page',page,'page_size',50);
end;$$;
revoke all on function public.olivia_contact_directory(integer,text,text,text) from public,anon,authenticated;
grant execute on function public.olivia_contact_directory(integer,text,text,text) to service_role;
