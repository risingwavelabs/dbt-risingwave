{#
  RisingWave DELETE accepts neither a target alias nor a USING clause, and
  RisingWave has no MERGE statement. These overrides keep dbt's delete+insert
  and microbatch semantics with SQL that RisingWave accepts.
#}

{% macro risingwave__get_delete_insert_merge_sql(target, source, unique_key, dest_columns, incremental_predicates) -%}
    {%- set dest_cols_csv = get_quoted_csv(dest_columns | map(attribute="name")) -%}

    {% if unique_key %}
        {% if unique_key is string %}
            {% set unique_key = [unique_key] %}
        {% endif %}

        {%- set unique_key_str = unique_key | join(', ') -%}
        {#- RisingWave rejects multi-column IN subqueries, so compare composite keys as row values. -#}
        {%- set key_expr = "row(" ~ unique_key_str ~ ")" if unique_key | length > 1 else unique_key_str -%}

        delete from {{ target }}
        where {{ key_expr }} in (
            select distinct {{ key_expr }}
            from {{ source }}
        )
        {%- if incremental_predicates %}
            {% for predicate in incremental_predicates %}
                and {{ predicate }}
            {% endfor %}
        {%- endif -%};

    {% endif %}

    insert into {{ target }} ({{ dest_cols_csv }})
    (
        select {{ dest_cols_csv }}
        from {{ source }}
    )

{%- endmacro %}

{% macro risingwave__get_incremental_microbatch_sql(arg_dict) %}
    {%- set target = arg_dict["target_relation"] -%}
    {%- set source = arg_dict["temp_relation"] -%}
    {%- set dest_columns = arg_dict["dest_columns"] -%}
    {%- set event_time = model.config.event_time -%}
    {%- set predicates = [] -%}
    {%- for predicate in (arg_dict.get("incremental_predicates") or []) -%}
        {%- do predicates.append(predicate) -%}
    {%- endfor -%}

    {%- set batch = model.batch if model.batch is defined else none -%}
    {%- set event_time_start = batch.event_time_start if batch else model.config.get("__dbt_internal_microbatch_event_time_start") -%}
    {%- set event_time_end = batch.event_time_end if batch else model.config.get("__dbt_internal_microbatch_event_time_end") -%}

    {%- if not event_time_start and not event_time_end -%}
        {{ exceptions.raise_compiler_error("RisingWave microbatch requires batch event time bounds; refusing to replace the whole target relation.") }}
    {%- endif -%}

    {#- Render bounds the same way dbt filters microbatch inputs. -#}
    {%- if event_time_start -%}
        {%- do predicates.append(event_time ~ " >= '" ~ event_time_start ~ "'") -%}
    {%- endif -%}
    {%- if event_time_end -%}
        {%- do predicates.append(event_time ~ " < '" ~ event_time_end ~ "'") -%}
    {%- endif -%}

    delete from {{ target }}
    where {{ predicates | join("\n      and ") }};

    {%- set dest_cols_csv = get_quoted_csv(dest_columns | map(attribute="name")) %}

    insert into {{ target }} ({{ dest_cols_csv }})
    (
        select {{ dest_cols_csv }}
        from {{ source }}
    )
{% endmacro %}
