-- The table already exists in Sadiet. This definition also supports local tests.
create table if not exists public.catalog_variations(
 id uuid primary key default gen_random_uuid(),catalog_product_id uuid not null references public.catalog_products(id) on delete cascade,
 woocommerce_variation_id bigint not null unique,sku text,name text,price numeric,regular_price numeric,sale_price numeric,
 on_sale boolean default false,purchasable boolean default false,stock_status text default 'unknown',stock_quantity integer,
 attributes jsonb default '[]',source_modified_at timestamptz,synced_at timestamptz default now(),created_at timestamptz default now(),updated_at timestamptz default now()
);
alter table public.catalog_variations add column if not exists status text not null default 'publish';
alter table public.catalog_variations add column if not exists is_active boolean not null default true;
alter table public.catalog_variations add column if not exists image_url text;
alter table public.catalog_variations add column if not exists permalink text;
alter table public.catalog_variations add column if not exists manage_stock boolean;
alter table public.catalog_products add column if not exists variations_synced_at timestamptz;
alter table public.catalog_products add column if not exists variations_sync_status text not null default 'pending';
create index if not exists catalog_variations_product_idx on public.catalog_variations(catalog_product_id);
alter table public.catalog_variations enable row level security;
revoke all on public.catalog_variations from public,anon,authenticated;
grant select,insert,update,delete on public.catalog_variations to service_role;

create or replace function public.sync_catalog_variations(p_snapshot jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare p public.catalog_products;v jsonb;seen bigint[];expected bigint[];n integer:=0;retired integer:=0;requested timestamptz:=(p_snapshot->>'requested_at')::timestamptz;
begin
 if p_snapshot->>'complete' is distinct from 'true' or jsonb_typeof(p_snapshot->'variations') is distinct from 'array' or jsonb_typeof(p_snapshot->'expected_ids') is distinct from 'array' or requested is null then raise exception 'Instantánea de variantes incompleta'; end if;
 select * into p from public.catalog_products where id=(p_snapshot->>'catalog_product_id')::uuid and woocommerce_product_id=(p_snapshot->>'woocommerce_product_id')::bigint for update;
 if not found or p.product_type<>'variable' then raise exception 'Producto padre no válido'; end if;
 if p.variations_synced_at>requested then return jsonb_build_object('skipped_stale',true,'catalog_product_id',p.id); end if;
 seen:=array(select (x->>'woocommerce_variation_id')::bigint from jsonb_array_elements(p_snapshot->'variations')x order by (x->>'woocommerce_variation_id')::bigint);
 expected:=array(select x::bigint from jsonb_array_elements_text(p_snapshot->'expected_ids')x order by x::bigint);
 if seen is distinct from expected or cardinality(seen)<>(select count(distinct x) from unnest(seen)x) or exists(select 1 from unnest(seen)x where x<=0) then raise exception 'La lista de variantes no coincide con el producto padre'; end if;
 for v in select * from jsonb_array_elements(p_snapshot->'variations') loop
  if exists(select 1 from public.catalog_variations where woocommerce_variation_id=(v->>'woocommerce_variation_id')::bigint and catalog_product_id<>p.id) then raise exception 'Variante vinculada a otro producto'; end if;
  if coalesce(v->>'status','') not in ('publish','private','draft','pending') or coalesce(v->>'stock_status','') not in ('instock','outofstock','onbackorder','unknown') or jsonb_typeof(v->'attributes') is distinct from 'array' then raise exception 'Datos de variante no válidos'; end if;
  if coalesce((v->>'price')::numeric,0)<0 or coalesce((v->>'regular_price')::numeric,0)<0 or coalesce((v->>'sale_price')::numeric,0)<0 then raise exception 'Precio de variante no válido'; end if;
  insert into public.catalog_variations(catalog_product_id,woocommerce_variation_id,sku,name,status,is_active,price,regular_price,sale_price,on_sale,purchasable,stock_status,stock_quantity,manage_stock,attributes,image_url,permalink,source_modified_at,synced_at)
  values(p.id,(v->>'woocommerce_variation_id')::bigint,nullif(v->>'sku',''),v->>'name',v->>'status',true,(v->>'price')::numeric,(v->>'regular_price')::numeric,(v->>'sale_price')::numeric,coalesce((v->>'on_sale')::boolean,false),coalesce((v->>'purchasable')::boolean,false),v->>'stock_status',(v->>'stock_quantity')::integer,(v->>'manage_stock')::boolean,v->'attributes',nullif(v->>'image_url',''),coalesce(nullif(v->>'permalink',''),p.permalink),(v->>'source_modified_at')::timestamptz,now())
  on conflict(woocommerce_variation_id) do update set sku=excluded.sku,name=excluded.name,status=excluded.status,is_active=true,price=excluded.price,regular_price=excluded.regular_price,sale_price=excluded.sale_price,on_sale=excluded.on_sale,purchasable=excluded.purchasable,stock_status=excluded.stock_status,stock_quantity=excluded.stock_quantity,manage_stock=excluded.manage_stock,attributes=excluded.attributes,image_url=excluded.image_url,permalink=excluded.permalink,source_modified_at=excluded.source_modified_at,synced_at=excluded.synced_at,updated_at=now();
  n:=n+1;
 end loop;
 update public.catalog_variations set is_active=false,purchasable=false,updated_at=now() where catalog_product_id=p.id and is_active and not(woocommerce_variation_id=any(seen));get diagnostics retired=row_count;
 update public.catalog_products set variations_synced_at=clock_timestamp(),variations_sync_status='complete' where id=p.id;
 return jsonb_build_object('catalog_product_id',p.id,'upserted',n,'retired',retired);
end;$$;

create or replace function public.olivia_catalog_product_context(p_id uuid,p_detailed boolean default false) returns jsonb
language sql set search_path='' as $$
 select jsonb_build_object('id',p.id,'name',p.name,'url',p.permalink,'price',p.price,'currency',p.currency,'stock_status',p.stock_status,'stock_quantity',p.stock_quantity,'synced_at',p.synced_at,'product_type',p.product_type,'attributes',p.attributes,'variations_synced_at',p.variations_synced_at,'variations_sync_status',p.variations_sync_status,
 'variation_count',(select count(*) from public.catalog_variations v where v.catalog_product_id=p.id and v.is_active and v.status='publish' and p.product_type='variable'))
 ||case when p_detailed then jsonb_build_object('variations',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'woocommerce_variation_id',v.woocommerce_variation_id,'name',v.name,'sku',v.sku,'attributes',v.attributes,'price',v.price,'regular_price',v.regular_price,'sale_price',v.sale_price,'on_sale',v.on_sale,'purchasable',v.purchasable,'stock_status',v.stock_status,'stock_quantity',v.stock_quantity,'url',v.permalink,'synced_at',v.synced_at) order by v.woocommerce_variation_id) from public.catalog_variations v where v.catalog_product_id=p.id and v.is_active and v.status='publish' and p.product_type='variable'),'[]')) else '{}'::jsonb end
 from public.catalog_products p where p.id=p_id;
$$;

create or replace function public.olivia_catalog_products() returns setof jsonb
language sql set search_path='' as $$
 select to_jsonb(p)||jsonb_build_object('variations',coalesce((select jsonb_agg(to_jsonb(v) order by v.woocommerce_variation_id) from public.catalog_variations v where v.catalog_product_id=p.id and v.is_active and p.product_type='variable'),'[]')) from public.catalog_products p order by p.name;
$$;
revoke all on function public.sync_catalog_variations(jsonb),public.olivia_catalog_product_context(uuid,boolean),public.olivia_catalog_products() from public,anon,authenticated;
grant execute on function public.sync_catalog_variations(jsonb),public.olivia_catalog_product_context(uuid,boolean),public.olivia_catalog_products() to service_role;
