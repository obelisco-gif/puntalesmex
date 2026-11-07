-- Existing live product columns omitted from the original minimal test fixture.
alter table public.catalog_products add column if not exists attributes jsonb default '[]';
alter table public.catalog_products add column if not exists sku text;
alter table public.catalog_products add column if not exists purchasable boolean default true;
alter table public.catalog_products add column if not exists on_sale boolean default false;
alter table public.catalog_products add column if not exists regular_price numeric;
alter table public.catalog_products add column if not exists sale_price numeric;

alter table public.catalog_products add column if not exists internal_notes text;

-- Minimal stand-in for the pre-existing parent upsert; exercises wrapper orchestration.
create function public.sync_catalog_product(payload jsonb) returns uuid language plpgsql as $$
declare pid uuid; begin
 insert into public.catalog_products(woocommerce_product_id,name,product_type)
 values((payload->>'woocommerce_product_id')::bigint,payload->>'name',payload->>'product_type')
 on conflict(woocommerce_product_id) do update set name=excluded.name,product_type=excluded.product_type
 returning id into pid;
 return pid;
end;$$;
