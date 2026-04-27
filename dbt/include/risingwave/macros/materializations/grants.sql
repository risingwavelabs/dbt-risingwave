{# RisingWave requires specifying the object type in GRANT/REVOKE statements.
   The default dbt macro emits `GRANT x ON relation` which RisingWave rejects
   for non-table objects. These overrides add the correct ON <type> clause. #}

{% macro risingwave__get_show_grant_sql(relation) %}
  with relation_acl as (
    select
      unnest(rw_relations.acl) as acl_entry
    from rw_catalog.rw_relations
    join rw_catalog.rw_schemas on rw_relations.schema_id = rw_schemas.id
    where rw_schemas.name = '{{ relation.schema }}'
      and rw_relations.name = '{{ relation.identifier }}'
  )
  select
    split_part(acl_entry, '=', 1) as grantee,
    case
      when split_part(split_part(acl_entry, '=', 2), '/', 1) = 'dwar' then 'all'
      when split_part(split_part(acl_entry, '=', 2), '/', 1) like '%r%' then 'select'
    end as privilege_type
  from relation_acl
  where split_part(acl_entry, '=', 1) not in ('root', 'rwadmin', 'postgres')
    and split_part(split_part(acl_entry, '=', 2), '/', 1) like '%r%'
{% endmacro %}

{%- macro risingwave__get_grant_sql(relation, privilege, grantees) -%}
    grant {{ privilege }} on
    {%- if relation.type == 'materialized_view' %} materialized view
    {%- elif relation.type == 'view' %} view
    {%- else %} table
    {%- endif %}
    {{ relation.render() }} to {{ grantees | join(', ') }}
{%- endmacro -%}


{%- macro risingwave__get_revoke_sql(relation, privilege, grantees) -%}
    revoke {{ privilege }} on
    {%- if relation.type == 'materialized_view' %} materialized view
    {%- elif relation.type == 'view' %} view
    {%- else %} table
    {%- endif %}
    {{ relation.render() }} from {{ grantees | join(', ') }}
{%- endmacro -%}
