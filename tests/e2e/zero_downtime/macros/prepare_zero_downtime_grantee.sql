{% macro prepare_zero_downtime_grantee() %}
  {% call statement('prepare_zero_downtime_grantee') %}
    drop user if exists dbt_e2e_zd_grantee;
    create user dbt_e2e_zd_grantee;
  {% endcall %}
{% endmacro %}
