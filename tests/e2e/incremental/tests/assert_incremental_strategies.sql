{% set expected_stage = env_var('DBT_RW_INCREMENTAL_EXPECT_STAGE', 'initial') %}

{% if expected_stage not in ['initial', 'incremental', 'full_refresh'] %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_INCREMENTAL_EXPECT_STAGE: " ~ expected_stage) }}
{% endif %}

{% if expected_stage == 'initial' %}
  {% set expected_upserts = [(1, 'alpha', 1), (2, 'beta', 1)] %}
  {% set expected_microbatch = [(1, 'mb_alpha'), (2, 'mb_beta')] %}
{% elif expected_stage == 'incremental' %}
  {% set expected_upserts = [(1, 'alpha_v2', 1), (2, 'beta', 1), (3, 'gamma', 2)] %}
  {% set expected_microbatch = [(1, 'mb_alpha'), (2, 'mb_beta_v2'), (3, 'mb_gamma')] %}
{% else %}
  {% set expected_upserts = [(10, 'reset_alpha', 3), (11, 'reset_beta', 3)] %}
  {% set expected_microbatch = [(1, 'mb_alpha'), (2, 'mb_beta_v2'), (3, 'mb_gamma')] %}
{% endif %}

{% for model_name in ['incremental_upsert', 'incremental_composite_upsert'] %}
select '{{ model_name }} row count mismatch' as failure
where (select count(*) from {{ ref(model_name) }}) != {{ expected_upserts | length }}

union all

select '{{ model_name }} has duplicate keys' as failure
where exists (
    select id, batch_id
    from {{ ref(model_name) }}
    group by id, batch_id
    having count(*) > 1
)

{% for id, payload, batch_id in expected_upserts %}
union all

select '{{ model_name }} missing row {{ id }}/{{ payload }}' as failure
where not exists (
    select 1 from {{ ref(model_name) }}
    where id = {{ id }} and payload = '{{ payload }}' and batch_id = {{ batch_id }}
)
{% endfor %}

union all
{% endfor %}

select 'incremental_microbatch row count mismatch' as failure
where (select count(*) from {{ ref('incremental_microbatch') }}) != {{ expected_microbatch | length }}

{% for id, payload in expected_microbatch %}
union all

select 'incremental_microbatch missing row {{ id }}/{{ payload }}' as failure
where not exists (
    select 1 from {{ ref('incremental_microbatch') }}
    where id = {{ id }} and payload = '{{ payload }}'
)
{% endfor %}

union all

select 'incremental runs must not leave __dbt_tmp tables behind' as failure
where exists (
    select 1
    from rw_relations
    where strpos(name, '__dbt_tmp') > 0
)
