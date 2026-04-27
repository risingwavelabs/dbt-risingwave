{% macro prepare_grants_docs_schema() %}
  {% call statement('prepare_grants_docs_schema') %}
    drop schema if exists {{ adapter.quote(target.schema) }} cascade;
    drop user if exists dbt_e2e_gds_grantee;
    drop user if exists dbt_e2e_gds_owner;
    create user dbt_e2e_gds_grantee;
    create user dbt_e2e_gds_owner;
  {% endcall %}
{% endmacro %}
