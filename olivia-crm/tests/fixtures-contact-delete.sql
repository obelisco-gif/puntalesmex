-- Remaining existing production tables needed for delete integration tests.
create table if not exists public.lead_magnet_deliveries(id uuid primary key default gen_random_uuid(),contact_id uuid references public.contacts(id) on delete cascade);
create table if not exists public.product_recommendations(id uuid primary key default gen_random_uuid(),contact_id uuid references public.contacts(id) on delete cascade);
