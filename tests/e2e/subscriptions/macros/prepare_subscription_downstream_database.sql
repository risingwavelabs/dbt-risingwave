{% macro prepare_subscription_downstream_database() %}
  {% do run_query("drop database if exists dbt_subscription_downstream") %}
  {% do run_query("create database dbt_subscription_downstream") %}
{% endmacro %}
