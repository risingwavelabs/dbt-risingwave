{# RisingWave requires specifying the object type in GRANT/REVOKE statements.
   The default dbt macro emits `GRANT x ON relation` which RisingWave rejects
   for non-table objects. These overrides add the correct ON <type> clause. #}

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
