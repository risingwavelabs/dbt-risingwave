{% materialization materialized_view, adapter='risingwave' %}
  {%- set identifier = model['alias'] -%}
  {%- set full_refresh_mode = should_full_refresh() -%}
  {%- set old_relation = adapter.get_relation(identifier=identifier,
                                              schema=schema,
                                              database=database) -%}
  {%- set target_relation = api.Relation.create(identifier=identifier,
                                                schema=schema,
                                                database=database,
                                                type='materialized_view') -%}

  {# If any table is backfilling, we short-circuit and wait until the database is in a stable-state #}
  {%- set is_any_job_running = run_query("SHOW JOBS;") | length > 0 -%}
  {% if is_any_job_running %}
    {{ exceptions.raise_compiler_error('There are jobs running, short-circuiting. Please wait until jobs are completed') }}
  {% endif %}

  {%- set hash = local_md5(sql) -%}
  {%- set has_current_mv_hash_changed_query = "SELECT coalesce((
        SELECT hash FROM relation_hashes WHERE target_relation = '" ~ target_relation ~ "'
      ) != '" ~ hash ~ "', true);" %}
  {%- set are_parent_mvs_droppable_query = "SELECT coalesce((
        SELECT definition FROM rw_materialized_views
        JOIN rw_schemas ON rw_schemas.id = rw_materialized_views.schema_id
        WHERE rw_schemas.name = '" ~ schema ~ "' AND rw_materialized_views.name = '" ~ identifier ~ "'
      ), '') ilike '%internal_droppable__%';" -%}
  {%- set has_current_mv_hash_changed = run_query(has_current_mv_hash_changed_query).columns[0][0] -%}
  {%- set are_parent_mvs_droppable = run_query(are_parent_mvs_droppable_query).columns[0][0] -%}
  {{ log("has_current_mv_hash_changed: " ~ has_current_mv_hash_changed) }}
  {{ log("are_parent_mvs_droppable: " ~ are_parent_mvs_droppable) }}

  {# Full-refresh avoids reusing existing relations and drops any table.
     We have to cascade in case the relation has dependencies. #}
  {% if (full_refresh_mode and old_relation) or (old_relation and old_relation.type != 'materialized_view') %}
    {{ log("Dropping relation {} to force full refresh/change type".format(old_relation)) }}
    {{ risingwave__drop_relation(old_relation) }}
    {%- set old_relation = none -%}
  {% endif %}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {{ log("Creating materialized view {}".format(config.get('deprecated'))) }}
  {% if config.get('deprecated') %}
    {% if old_relation is not none %}
      {# If the relation is deprecated, we can just drop it #}
      {{ log("Dropping relation {} as it is deprecated".format(old_relation)) }}
      {{ risingwave__drop_relation(old_relation) }}
    {% endif %}
    {% call statement('main') -%}
    select 1;
    {%- endcall %}
  {% elif old_relation is none %}
    {# If there is no previous relation, we can just create the current MV directly #}
    {{ log ("Creating relation {} as {}".format(target_relation, sql)) }}
    {% call statement('main') -%}
      INSERT INTO relation_hashes (target_relation, hash)
      VALUES ('{{ target_relation }}', '{{ hash }}')
      ;
      {{ risingwave__create_materialized_view_as(target_relation, sql) }}
      FLUSH;
    {%- endcall %}

    {# TODO(vlad): Reaching this statement takes a long while... #}
    {{ create_indexes(target_relation) }}
  {%- elif has_current_mv_hash_changed or are_parent_mvs_droppable -%}
    {# We have to switch-over to the new version without causing downtime #}
    {{ log("Found change in relations...") }}
    {%- set temp_relation = api.Relation.create(identifier="internal_tmp__" ~ target_relation.identifier,
                                                schema=target_relation.schema,
                                                database=target_relation.database,
                                                type='materialized_view') -%}
    {%- set temp_relation_exists = adapter.get_relation(schema=temp_relation.schema,
                                                        identifier=temp_relation.identifier,
                                                        database=temp_relation.database) -%}
    {%- set has_temp_relation_hash_changed_query = "SELECT coalesce((
        SELECT hash FROM relation_hashes WHERE target_relation = '" ~ temp_relation ~ "'
    ) != '" ~ hash ~ "', true);" -%}
    {%- set are_temp_parent_mvs_droppable_query = "SELECT coalesce((
        SELECT definition FROM rw_materialized_views
        JOIN rw_schemas ON rw_schemas.id = rw_materialized_views.schema_id
        WHERE rw_schemas.name = '" ~ schema ~ "' AND rw_materialized_views.name = '" ~ temp_relation.identifier ~ "'
      ), '') ilike '%internal_droppable__%';" -%}
    {%- set has_temp_relation_hash_changed = run_query(has_temp_relation_hash_changed_query).columns[0][0] -%}
    {%- set are_temp_parent_mvs_droppable = run_query(are_temp_parent_mvs_droppable_query).columns[0][0] -%}
    {{ log("has_temp_relation_hash_changed: " ~ has_temp_relation_hash_changed) }}
    {{ log("are_temp_parent_mvs_droppable: " ~ are_temp_parent_mvs_droppable) }}

    {# If the current tmp table isn't for the current MV, we have to drop it and start over #}
    {%- if temp_relation_exists and (has_temp_relation_hash_changed or are_temp_parent_mvs_droppable) -%}
      {{ log("Dropping temp relation {} as it's not current".format(temp_relation)) }}
      {{ risingwave__drop_relation(temp_relation) }}
      {%- set temp_relation_exists = false -%}
    {%- endif -%}

    {%- if not temp_relation_exists -%}
      {{ log("Creating temp relation {} as {}".format(temp_relation, sql)) }}
      {% call statement('main') -%}
        INSERT INTO relation_hashes (target_relation, hash)
        VALUES ('{{ temp_relation }}', '{{ hash }}')
        ;
        {{ risingwave__create_materialized_view_as(temp_relation, sql) }}
        FLUSH;
      {%- endcall %}
    {%- endif -%}

    {{ create_indexes(temp_relation) }}

    {# The tmp exists and is initialized, we just need to swap it #}
    {%- set droppable_old_relation = api.Relation.create(identifier="internal_droppable__" ~ target_relation.identifier,
                                                schema=target_relation.schema,
                                                database=target_relation.database,
                                                type='materialized_view') -%}
    {{ log("Swapping relation {} with {}".format(old_relation, target_relation)) }}

    {% call statement('main') -%}
      ALTER MATERIALIZED VIEW {{ temp_relation }} SWAP WITH {{ target_relation }};
      INSERT INTO relation_hashes (target_relation, hash) VALUES ('{{ target_relation }}', '{{ hash }}');
      DELETE FROM relation_hashes WHERE target_relation = '{{ temp_relation }}';
      FLUSH;
      ALTER MATERIALIZED VIEW {{ temp_relation }} RENAME TO {{ droppable_old_relation.identifier }};
      FLUSH;
    {%- endcall %}
  {% else %}
    {{ log("No change in relations") }}
    {{ risingwave__handle_on_configuration_change(old_relation, target_relation) }}
  {% endif %}

  {% do persist_docs(target_relation, model) %}

  {{ run_hooks(post_hooks, inside_transaction=False) }}
  {{ run_hooks(post_hooks, inside_transaction=True) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
