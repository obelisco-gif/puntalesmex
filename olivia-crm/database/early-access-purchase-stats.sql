create or replace function public.olivia_early_access_purchase_stats()
returns jsonb
language sql stable
set search_path = ''
as $$
with enrolled as (
 select c.id, (select min(coalesce(nullif(e.metadata->>'submitted_at','')::timestamptz,e.occurred_at))
    from public.contact_events e where e.contact_id=c.id and e.event_type='early_access_registered') as enrolled_at
 from public.contacts c
 where coalesce(c.source,'') <> 'qa_test' and 'bf2026_early_access'=any(c.manual_tags)
), classified as (
 select e.enrolled_at, exists (
  select 1 from public.woo_orders o
  where o.contact_id=e.id and o.match_status='matched'
    and o.status not in ('failed','pending','cancelled','refunded')
    and (o.paid_at is not null or o.status='completed')
    and coalesce(o.paid_at,o.created_at_woo)<e.enrolled_at
 ) as has_prior_purchase
 from enrolled e
)
select jsonb_build_object(
 'with_prior_purchase',count(*) filter(where enrolled_at is not null and has_prior_purchase),
 'without_identified_prior_purchase',count(*) filter(where enrolled_at is not null and not has_prior_purchase),
 'unknown_registration_date',count(*) filter(where enrolled_at is null))
from classified
$$;
revoke all on function public.olivia_early_access_purchase_stats() from public, anon, authenticated;
grant execute on function public.olivia_early_access_purchase_stats() to service_role;
