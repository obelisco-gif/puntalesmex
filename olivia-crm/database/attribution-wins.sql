create or replace function public.olivia_attribution_panels()
returns jsonb
language sql
security invoker
set search_path = public
as $$
with early_contacts as (
  select distinct contact_id from contact_events where event_type = 'early_access_registered' and contact_id is not null
), early_ranked as (
  select ec.contact_id, coalesce(nullif(t.source,''), nullif(t.channel,''), 'Sin atribución') as source,
    coalesce(nullif(t.campaign,''), 'Sin campaña identificada') as campaign,
    row_number() over (partition by ec.contact_id order by t.occurred_at asc, t.id asc) as rn
  from early_contacts ec left join attribution_touchpoints t on t.contact_id = ec.contact_id
), early_rows as (
  select source, campaign, count(*)::integer as registrations from early_ranked where rn = 1 group by source, campaign
), eligible_orders as (
  select o.id, o.contact_id, coalesce(o.paid_at, o.created_at_woo) as purchased_at,
    greatest(coalesce(o.total,0) - coalesce(o.refunded_total,0),0) as revenue
  from woo_orders o
  where o.contact_id is not null and coalesce(o.status,'') not in ('cancelled','failed','refunded','trash')
    and (o.paid_at is not null or o.status in ('processing','completed','on-hold'))
), purchase_ranked as (
  select o.id, o.revenue, coalesce(nullif(t.source,''), nullif(t.channel,''), 'Sin atribución') as source,
    coalesce(nullif(t.campaign,''), 'Sin campaña identificada') as campaign,
    row_number() over (partition by o.id order by t.occurred_at desc nulls last, t.id desc nulls last) as rn
  from eligible_orders o left join attribution_touchpoints t on t.contact_id = o.contact_id and t.occurred_at <= o.purchased_at
), purchase_rows as (
  select source, campaign, count(*)::integer as orders, coalesce(sum(revenue),0)::numeric as revenue from purchase_ranked where rn = 1 group by source, campaign
)
select jsonb_build_object(
  'early_access', coalesce((select jsonb_agg(jsonb_build_object('source',source,'campaign',campaign,'registrations',registrations) order by registrations desc, source, campaign) from early_rows),'[]'::jsonb),
  'purchases', coalesce((select jsonb_agg(jsonb_build_object('source',source,'campaign',campaign,'orders',orders,'revenue',revenue) order by orders desc, revenue desc, source, campaign) from purchase_rows),'[]'::jsonb)
);
$$;

revoke all on function public.olivia_attribution_panels() from public;
grant execute on function public.olivia_attribution_panels() to service_role;
