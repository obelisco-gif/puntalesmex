-- Read-only WooCommerce import; it never changes an order or marketing consent.
create table public.woo_orders (
 id bigint primary key,order_number text not null,customer_id bigint,status text not null,
 billing_email text,billing_phone text,billing_first_name text,
 currency text not null,total numeric(12,2) not null check(total>=0),refunded_total numeric(12,2) not null default 0 check(refunded_total>=0),
 created_at_woo timestamptz not null,paid_at timestamptz,source_modified_at timestamptz not null,
 contact_id uuid references public.contacts(id) on delete set null,
 match_status text not null default 'unmatched' check(match_status in ('matched','unmatched','ambiguous','conflict')),
 matched_by text,synced_at timestamptz not null default clock_timestamp()
);
create index woo_orders_contact on public.woo_orders(contact_id,created_at_woo desc);
create index woo_orders_email on public.woo_orders(billing_email);
create index woo_orders_phone on public.woo_orders(billing_phone);
create table public.woo_order_items (
 order_id bigint not null references public.woo_orders(id) on delete cascade,line_id bigint not null,
 woocommerce_product_id bigint,variation_id bigint,name text not null,quantity integer not null check(quantity>0),
 total numeric(12,2) not null check(total>=0),primary key(order_id,line_id)
);
create index woo_order_items_product on public.woo_order_items(woocommerce_product_id);
alter table public.woo_orders enable row level security;
alter table public.woo_order_items enable row level security;
revoke all on public.woo_orders,public.woo_order_items from public,anon,authenticated;
grant all on public.woo_orders,public.woo_order_items to service_role;
insert into public.olivia_config(key,value) values('woo_orders','{"enabled":false,"cursor":null,"last_sync":null,"history_complete":false}') on conflict(key) do nothing;

create function public.olivia_normalize_phone(p_phone text,p_country text default null) returns text language plpgsql immutable security invoker set search_path='' as $$
declare digits text:=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g');
begin
 if left(digits,2)='00' then digits:=substr(digits,3); end if;
 if upper(p_country)='ES' and length(digits)=9 and digits ~ '^[6789]' then digits:='34'||digits; end if;
 if digits ~ '^[1-9][0-9]{9,14}$' then return '+'||digits; end if;
 return null;
end;$$;

create index contacts_woo_email_idx on public.contacts(lower(btrim(email)));
create index contacts_woo_phone_idx on public.contacts(public.olivia_normalize_phone(phone));

create function public.olivia_woo_is_purchase(p_status text,p_paid timestamptz,p_total numeric,p_refunded numeric) returns boolean language sql immutable security invoker set search_path='' as $$
 select (p_status in ('processing','completed') or (p_paid is not null and p_status !~ '(cancel|refund|fail|draft|trash)')) and not (p_refunded>0 and p_refunded>=p_total);
$$;

create function public.olivia_link_woo_order(p_order bigint) returns void language plpgsql security invoker set search_path='' as $$
declare o public.woo_orders; ids uuid[]; cid uuid; count_value int; state text; method text;
begin
 select * into o from public.woo_orders where id=p_order for update;
 if not found then return; end if;
 select array_agg(distinct id) into ids from public.contacts where
  (o.billing_email is not null and lower(btrim(email))=o.billing_email) or
  (o.billing_phone is not null and public.olivia_normalize_phone(phone)=o.billing_phone);
 count_value:=coalesce(cardinality(ids),0);
 if count_value=1 then
  cid:=ids[1];
  if exists(select 1 from public.contacts where id=cid and o.billing_email is not null and email is not null and lower(btrim(email))<>o.billing_email) then cid:=null;state:='conflict';
  else
   state:='matched';
   select case when lower(btrim(email))=o.billing_email and public.olivia_normalize_phone(phone)=o.billing_phone then 'email_and_phone' when lower(btrim(email))=o.billing_email then 'email' else 'phone' end into method from public.contacts where id=cid;
  end if;
 elsif count_value>1 then state:='ambiguous'; else state:='unmatched'; end if;
 update public.woo_orders set contact_id=cid,match_status=state,matched_by=method where id=o.id;
 if cid is not null then
  update public.contacts set first_name=coalesce(nullif(first_name,''),nullif(o.billing_first_name,'')),
   preferences=case when nullif(first_name,'') is null and nullif(o.billing_first_name,'') is not null then preferences||'{"name_source":"woocommerce"}'::jsonb else preferences end,
   stage=case when public.olivia_woo_is_purchase(o.status,o.paid_at,o.total,o.refunded_total) and stage<>'unsubscribed' then 'customer' else stage end,updated_at=clock_timestamp() where id=cid;
  update public.lead_states set phase=(select stage from public.contacts where id=cid),updated_at=clock_timestamp() where contact_id=cid;
 end if;
end;$$;

create function public.olivia_ingest_woo_orders(p_orders jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare o jsonb; item jsonb; oid bigint; processed int:=0; matched int:=0; status_value text;
begin
 if jsonb_typeof(p_orders)<>'array' or jsonb_array_length(p_orders)>100 then raise exception 'Expected at most 100 normalized orders'; end if;
 for o in select value from jsonb_array_elements(p_orders) loop
  oid:=null;status_value:=o->>'status';
  if status_value is null or status_value !~ '^[a-z][a-z0-9-]{0,60}$' then raise exception 'Invalid WooCommerce order status'; end if;
  insert into public.woo_orders(id,order_number,customer_id,status,billing_email,billing_phone,billing_first_name,currency,total,refunded_total,created_at_woo,paid_at,source_modified_at)
  values((o->>'id')::bigint,left(o->>'order_number',100),nullif(o->>'customer_id','')::bigint,status_value,nullif(lower(btrim(o->>'billing_email')),''),public.olivia_normalize_phone(o->>'billing_phone',o->>'billing_country'),left(o->>'billing_first_name',100),o->>'currency',(o->>'total')::numeric,coalesce((o->>'refunded_total')::numeric,0),(o->>'created_at_woo')::timestamptz,nullif(o->>'paid_at','')::timestamptz,(o->>'source_modified_at')::timestamptz)
  on conflict(id) do update set order_number=excluded.order_number,customer_id=excluded.customer_id,status=excluded.status,billing_email=excluded.billing_email,billing_phone=excluded.billing_phone,billing_first_name=excluded.billing_first_name,currency=excluded.currency,total=excluded.total,refunded_total=excluded.refunded_total,created_at_woo=excluded.created_at_woo,paid_at=excluded.paid_at,source_modified_at=excluded.source_modified_at,synced_at=clock_timestamp()
   where excluded.source_modified_at>=public.woo_orders.source_modified_at returning id into oid;
  if oid is null then continue; end if;
  delete from public.woo_order_items where order_id=oid;
  for item in select value from jsonb_array_elements(coalesce(o->'items','[]')) loop
   insert into public.woo_order_items(order_id,line_id,woocommerce_product_id,variation_id,name,quantity,total)
   values(oid,(item->>'line_id')::bigint,nullif(item->>'product_id','')::bigint,nullif(item->>'variation_id','')::bigint,left(item->>'name',300),(item->>'quantity')::int,(item->>'total')::numeric);
  end loop;
  perform public.olivia_link_woo_order(oid);
  processed:=processed+1;
  if exists(select 1 from public.woo_orders where id=oid and contact_id is not null) then matched:=matched+1; end if;
 end loop;
 return jsonb_build_object('processed',processed,'matched',matched);
end;$$;

create function public.olivia_relink_contact_orders() returns trigger language plpgsql security invoker set search_path='' as $$
declare oid bigint;
begin
 for oid in select id from public.woo_orders where billing_email=lower(btrim(new.email)) or billing_phone=public.olivia_normalize_phone(new.phone) or contact_id=new.id loop perform public.olivia_link_woo_order(oid); end loop;
 return new;
end;$$;
create trigger olivia_relink_woo_orders after insert or update of email,phone on public.contacts for each row execute function public.olivia_relink_contact_orders();

create function public.olivia_purchase_history(p_contact uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
 'source','woocommerce','last_sync',(select value->'last_sync' from public.olivia_config where key='woo_orders'),
 'history_complete',coalesce((select (value->>'history_complete')::boolean from public.olivia_config where key='woo_orders'),false),
 'order_count',(select count(*) from public.woo_orders where contact_id=p_contact and status not in ('trash','checkout-draft','draft')),
 'purchase_count',(select count(*) from public.woo_orders where contact_id=p_contact and public.olivia_woo_is_purchase(status,paid_at,total,refunded_total)),
 'last_purchase_at',(select max(coalesce(paid_at,created_at_woo)) from public.woo_orders where contact_id=p_contact and public.olivia_woo_is_purchase(status,paid_at,total,refunded_total)),
 'usual_products',coalesce((select jsonb_agg(to_jsonb(t)) from (
  select i.woocommerce_product_id as product_id,max(i.name) as name,count(distinct o.id) as orders,sum(i.quantity) as units,max(coalesce(o.paid_at,o.created_at_woo)) as last_purchase_at
  from public.woo_orders o join public.woo_order_items i on i.order_id=o.id where o.contact_id=p_contact and public.olivia_woo_is_purchase(o.status,o.paid_at,o.total,o.refunded_total) and o.refunded_total=0
  group by coalesce(i.woocommerce_product_id::text,i.name),i.woocommerce_product_id having count(distinct o.id)>=2 order by count(distinct o.id) desc,sum(i.quantity) desc limit 5)t),'[]'),
 'recent_orders',coalesce((select jsonb_agg(to_jsonb(t) order by created_at_woo desc) from (
  select id,order_number,status,currency,total,refunded_total,created_at_woo,paid_at,synced_at,
  (select coalesce(jsonb_agg(jsonb_build_object('product_id',i.woocommerce_product_id,'variation_id',i.variation_id,'name',i.name,'quantity',i.quantity,'catalog_product_id',cp.id)),'[]') from public.woo_order_items i left join public.catalog_products cp on cp.woocommerce_product_id=i.woocommerce_product_id where i.order_id=o.id) as items
  from public.woo_orders o where contact_id=p_contact and status not in ('trash','checkout-draft','draft') order by created_at_woo desc limit 5)t),'[]'));
$$;

create function public.olivia_complete_woo_sync(p_until timestamptz) returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if p_until>now()+interval '5 minutes' then raise exception 'Invalid future synchronization cursor'; end if;
 update public.olivia_config set value=value||jsonb_build_object('cursor',greatest(nullif(value->>'cursor','')::timestamptz,p_until),'last_sync',now(),'history_complete',true),updated_at=now() where key='woo_orders';
 return jsonb_build_object('completed',true,'cursor',p_until);
end;$$;
revoke all on function public.olivia_woo_is_purchase(text,timestamptz,numeric,numeric),public.olivia_normalize_phone(text,text),public.olivia_link_woo_order(bigint),public.olivia_ingest_woo_orders(jsonb),public.olivia_relink_contact_orders(),public.olivia_purchase_history(uuid),public.olivia_complete_woo_sync(timestamptz) from public,anon,authenticated;
grant execute on function public.olivia_woo_is_purchase(text,timestamptz,numeric,numeric),public.olivia_normalize_phone(text,text),public.olivia_link_woo_order(bigint),public.olivia_ingest_woo_orders(jsonb),public.olivia_purchase_history(uuid),public.olivia_complete_woo_sync(timestamptz) to service_role;

