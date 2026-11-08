begin;
do $$
declare c uuid; old_chat uuid; new_chat uuid; first_page jsonb; second_page jsonb; r jsonb; n integer;
begin
 insert into public.contacts(email,first_name,stage,manual_tags) select 'directory-'||i||'@example.invalid','Directory fixture '||i,'qualified',array['bf2026_early_access'] from generate_series(1,61)i;
 insert into public.contacts(email,first_name,source) values('directory-hidden@example.invalid','Directory fixture hidden','qa_test');
 select id into c from public.contacts where email='directory-1@example.invalid';
 insert into public.conversations(contact_id,channel,updated_at) values(c,'whatsapp',now()-interval '1 hour') returning id into old_chat;
 insert into public.conversations(contact_id,channel,updated_at) values(c,'email',now()) returning id into new_chat;
 first_page:=public.olivia_contact_directory(1,'Directory fixture','','');
 second_page:=public.olivia_contact_directory(2,'Directory fixture','','');
 if (first_page->>'total')::integer<>61 or jsonb_array_length(first_page->'rows')<>50 or jsonb_array_length(second_page->'rows')<>11 then raise exception 'Contact pages incorrect or QA leaked'; end if;
 select count(distinct x->>'id') into n from jsonb_array_elements((first_page->'rows')||(second_page->'rows')) x;
 if n<>61 then raise exception 'Contact pagination duplicates or misses rows'; end if;
 r:=public.olivia_contact_directory(1,'directory-1@example.invalid','qualified','bf2026_early_access');
 if (r->>'total')::integer<>1 or r->'rows'->0->>'conversation_id'<>new_chat::text then raise exception 'Contact must link to newest conversation'; end if;
 r:=public.olivia_contact_directory(1,'directory-2@example.invalid','','');
 if r->'rows'->0->>'conversation_id' is not null or public.olivia_contact_detail((r->'rows'->0->>'id')::uuid) is null then raise exception 'Contact without chat must keep its detail'; end if;
 if (public.olivia_contact_directory(1,'Directory fixture','customer','')->>'total')::integer<>0 then raise exception 'Stage filter failed'; end if;
 if (public.olivia_contact_directory(1,'Directory fixture','','other_tag')->>'total')::integer<>0 then raise exception 'Tag filter failed'; end if;
 if has_function_privilege('anon','public.olivia_contact_directory(integer,text,text,text)','execute') then raise exception 'Contact directory publicly exposed'; end if;
end;$$;
select 'PASS: all contacts paginated, stable tie ordering, filters, newest conversation link, no-chat contact detail and QA exclusion.' as result;
rollback;
