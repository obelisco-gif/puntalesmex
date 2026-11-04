-- Olivia only. Commercial memory and conversation registration; no sends.
alter table public.contacts drop constraint contacts_stage_check;
alter table public.contacts add constraint contacts_stage_check check(stage in ('new','engaged','qualified','recommended','purchase_intent','customer','on_hold','lost','unsubscribed'));

create table public.contact_commercial_entries (
 id uuid primary key default gen_random_uuid(),
 contact_id uuid not null references public.contacts(id) on delete cascade,
 kind text not null check(kind in ('interest','avoid','order_inquiry','purchase')),
 product_id uuid references public.catalog_products(id) on delete set null,
 reference text not null default '',
 details text not null check(length(details) between 1 and 2000),
 status text not null default 'open' check(status in ('open','resolved','declared','confirmed','cancelled')),
 amount numeric(12,2) check(amount>=0),
 currency text not null default 'EUR' check(currency ~ '^[A-Z]{3}$'),
 quantity integer check(quantity between 1 and 10000),
 occurred_on date not null default current_date,
 source text not null check(source in ('crm','conversation')),
 evidence text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(kind='purchase' or amount is null),
 check(source<>'conversation' or (kind<>'purchase' and status<>'confirmed'))
);
create index contact_commercial_entries_contact on public.contact_commercial_entries(contact_id,updated_at desc);
create index contact_commercial_entries_product on public.contact_commercial_entries(product_id);
create unique index contact_commercial_entries_reference on public.contact_commercial_entries(contact_id,kind,reference) where reference<>'';
alter table public.contact_commercial_entries enable row level security;
revoke all on public.contact_commercial_entries from anon,authenticated;
grant all on public.contact_commercial_entries to service_role;

create function public.olivia_contact_score(p_contact uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.contacts; points int; reasons jsonb:='[]'; override_value int;
begin
 select * into c from public.contacts where id=p_contact;
 points:=case c.stage when 'engaged' then 15 when 'qualified' then 35 when 'recommended' then 45 when 'purchase_intent' then 65 when 'customer' then 70 else 0 end;
 reasons:=jsonb_build_array(jsonb_build_object('reason','Fase comercial','points',points));
 if 'bf2026_early_access'=any(c.manual_tags) then points:=points+15; reasons:=reasons||jsonb_build_array(jsonb_build_object('reason','Early Access','points',15)); end if;
 if exists(select 1 from public.contact_commercial_entries where contact_id=c.id and kind='interest' and product_id is not null and status<>'cancelled') then points:=points+10; reasons:=reasons||jsonb_build_array(jsonb_build_object('reason','Interés declarado en producto','points',10)); end if;
 if exists(select 1 from public.contact_commercial_entries where contact_id=c.id and kind='purchase' and status='confirmed') then points:=points+20; reasons:=reasons||jsonb_build_array(jsonb_build_object('reason','Compra confirmada en CRM','points',20)); end if;
 if c.stage in ('lost','unsubscribed') then points:=0; end if;
 override_value:=(c.preferences#>>'{commercial,score_override}')::int;
 return jsonb_build_object('value',coalesce(override_value,least(100,points)),'automatic',least(100,points),'manual',override_value is not null,'reasons',reasons);
end;$$;

create function public.olivia_save_contact(p_id uuid,p_input jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.contacts; profile jsonb:=coalesce(p_input->'commercial','{}'); k text;
begin
 select * into c from public.contacts where id=p_id for update;
 if not found then raise exception 'Contacto no encontrado'; end if;
 if nullif(p_input->>'expected_updated_at','')::timestamptz is distinct from c.updated_at then raise exception 'El contacto ha cambiado. Actualiza la ficha antes de guardar.'; end if;
 for k in select jsonb_object_keys(profile) loop
  if k not in ('tastes','objections','buying_horizon','score_override') then raise exception 'Atributo no válido'; end if;
 end loop;
 if jsonb_typeof(profile)<>'object' or length(coalesce(profile->>'tastes',''))>2000 or length(coalesce(profile->>'objections',''))>2000 or length(coalesce(profile->>'buying_horizon',''))>500 then raise exception 'Atributos no válidos'; end if;
 if profile->>'score_override' is not null and (profile->>'score_override')::int not between 0 and 100 then raise exception 'Score entre 0 y 100'; end if;
 update public.contacts set stage=coalesce(p_input->>'stage',stage),internal_notes=left(coalesce(p_input->>'internal_notes',internal_notes),10000),
 assigned_to=case when p_input ? 'assigned_to' then nullif(left(p_input->>'assigned_to',100),'') else assigned_to end,
 manual_tags=case when p_input ? 'manual_tags' then array(select distinct jsonb_array_elements_text(p_input->'manual_tags')) else manual_tags end,
 preferences=jsonb_set(preferences,'{commercial}',coalesce(preferences->'commercial','{}')||profile),updated_at=clock_timestamp()
 where id=p_id returning * into c;
 return to_jsonb(c);
end;$$;

create function public.olivia_save_commercial_entry(p_contact uuid,p_entry jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare e public.contact_commercial_entries; kind_value text:=p_entry->>'kind'; ref text:=left(btrim(coalesce(p_entry->>'reference','')),120);
begin
 perform 1 from public.contacts where id=p_contact for update;
 if not found then raise exception 'Contacto no encontrado'; end if;
 if kind_value='purchase' and ref='' then raise exception 'La compra requiere referencia de pedido'; end if;
 if kind_value in ('interest','avoid') and nullif(p_entry->>'product_id','') is not null then ref:='product:'||(p_entry->>'product_id'); end if;
 insert into public.contact_commercial_entries(contact_id,kind,product_id,reference,details,status,amount,currency,quantity,occurred_on,source)
 values(p_contact,kind_value,nullif(p_entry->>'product_id','')::uuid,ref,p_entry->>'details',coalesce(p_entry->>'status','open'),nullif(p_entry->>'amount','')::numeric,coalesce(p_entry->>'currency','EUR'),nullif(p_entry->>'quantity','')::int,coalesce(nullif(p_entry->>'occurred_on','')::date,current_date),'crm')
 on conflict(contact_id,kind,reference) where reference<>'' do update set product_id=excluded.product_id,details=excluded.details,status=excluded.status,amount=excluded.amount,currency=excluded.currency,quantity=excluded.quantity,occurred_on=excluded.occurred_on,source='crm',updated_at=clock_timestamp() returning * into e;
 update public.contacts set stage=case when kind_value='purchase' and e.status='confirmed' then 'customer' else stage end,updated_at=clock_timestamp() where id=p_contact;
 return to_jsonb(e);
end;$$;

revoke all on function public.olivia_contact_score(uuid),public.olivia_save_contact(uuid,jsonb),public.olivia_save_commercial_entry(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.olivia_contact_score(uuid),public.olivia_save_contact(uuid,jsonb),public.olivia_save_commercial_entry(uuid,jsonb) to service_role;

create function public.olivia_dashboard_contacts() returns setof jsonb language sql security invoker set search_path='' as $$
 select to_jsonb(c)||jsonb_build_object('score',public.olivia_contact_score(c.id),'commercial_entries',coalesce((select jsonb_agg(to_jsonb(e) order by e.updated_at desc) from public.contact_commercial_entries e where e.contact_id=c.id),'[]'::jsonb))
 from public.contacts c order by c.updated_at desc limit 100;
$$;
revoke all on function public.olivia_dashboard_contacts() from public,anon,authenticated;
grant execute on function public.olivia_dashboard_contacts() to service_role;
