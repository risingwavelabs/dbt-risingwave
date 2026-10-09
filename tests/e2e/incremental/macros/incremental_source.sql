{% macro incremental_source_relation() %}
  {{ return(api.Relation.create(
      identifier='incremental_input',
      schema=target.schema,
      database=target.database,
      type='table'
  )) }}
{% endmacro %}

{% macro microbatch_source_relation() %}
  {{ return(api.Relation.create(
      identifier='microbatch_input',
      schema=target.schema,
      database=target.database,
      type='table'
  )) }}
{% endmacro %}

{% macro setup_initial_incremental_source() %}
  {% set relation = incremental_source_relation() %}
  {% set microbatch_relation = microbatch_source_relation() %}

  {% call statement('setup_initial_incremental_source') %}
    drop table if exists {{ relation }};
    create table {{ relation }} (
      id int,
      payload varchar,
      batch_id int
    );
    insert into {{ relation }} values
      (1, 'alpha', 1),
      (2, 'beta', 1);

    drop table if exists {{ microbatch_relation }};
    create table {{ microbatch_relation }} (
      id int,
      payload varchar,
      event_ts timestamptz
    );
    -- id 1 stays outside the lookback window; id 2 is inside it on the next run.
    insert into {{ microbatch_relation }} values
      (1, 'mb_alpha', now() - interval '5 days'),
      (2, 'mb_beta', now() - interval '1 day');
  {% endcall %}
{% endmacro %}

{% macro append_incremental_source() %}
  {% set relation = incremental_source_relation() %}

  {% set microbatch_relation = microbatch_source_relation() %}

  {% call statement('append_incremental_source') %}
    insert into {{ relation }} values
      (3, 'gamma', 2);
    update {{ relation }} set payload = 'alpha_v2' where id = 1;

    update {{ microbatch_relation }} set payload = 'mb_beta_v2' where id = 2;
    insert into {{ microbatch_relation }} values
      (3, 'mb_gamma', now());
  {% endcall %}
{% endmacro %}

{% macro reset_incremental_source_for_full_refresh() %}
  {% set relation = incremental_source_relation() %}

  {% call statement('reset_incremental_source_for_full_refresh') %}
    drop table if exists {{ relation }};
    create table {{ relation }} (
      id int,
      payload varchar,
      batch_id int
    );
    insert into {{ relation }} values
      (10, 'reset_alpha', 3),
      (11, 'reset_beta', 3);
  {% endcall %}
{% endmacro %}
