{# Grants are applied to the new relation before the swap, so they must be present on
   the canonical name after every stage. #}
{% for model_name in ['zd_events_mv', 'zd_base_view', 'zd_switch_view_to_mv', 'zd_switch_mv_to_view'] %}
{% if not loop.first %}
union all
{% endif %}

select '{{ model_name }} must grant select to dbt_e2e_zd_grantee' as failure
where not exists (
    select 1
    from rw_catalog.rw_relations r
    join rw_catalog.rw_schemas s on s.id = r.schema_id
    where s.name = '{{ target.schema }}'
      and r.name = '{{ model_name }}'
      and array_to_string(r.acl, ',') like '%dbt_e2e_zd_grantee=r/%'
)
{% endfor %}
