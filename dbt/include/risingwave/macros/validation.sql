{% macro risingwave__validation_mode() -%}
  {%- set mode = var('risingwave_adapter_validation', 'warn') -%}
  {%- if mode is none -%}
    {{ return('warn') }}
  {%- endif -%}
  {%- set normalized_mode = mode | string | lower | trim -%}
  {%- if normalized_mode in ['warn', 'error', 'off'] -%}
    {{ return(normalized_mode) }}
  {%- endif -%}

  {{ exceptions.raise_compiler_error(
    "`risingwave_adapter_validation` must be one of `warn`, `error`, or `off`, got `" ~ mode ~ "`."
  ) }}
{%- endmacro %}


{% macro risingwave__validation_report(code, message) -%}
  {%- set mode = risingwave__validation_mode() -%}
  {%- set formatted_message = "[dbt-risingwave " ~ code ~ "] " ~ message -%}
  {%- if mode == 'off' -%}
  {%- elif mode == 'error' -%}
    {{ exceptions.raise_compiler_error(formatted_message) }}
  {%- else -%}
    {{ exceptions.warn(formatted_message) }}
  {%- endif -%}
{%- endmacro %}


{% macro risingwave__looks_like_ddl(sql) -%}
  {%- set normalized_sql = (sql | default('', true)) | trim | lower -%}
  {%- if normalized_sql.startswith('create ')
      or normalized_sql.startswith('drop ')
      or normalized_sql.startswith('alter ')
      or normalized_sql.startswith('truncate ') -%}
    {{ return(true) }}
  {%- endif -%}
  {{ return(false) }}
{%- endmacro %}


{% macro risingwave__validate_ignored_index_options(materialization) -%}
  {%- set indexes = config.get('indexes', []) -%}
  {%- if indexes is none -%}
    {%- set indexes = [] -%}
  {%- endif -%}

  {%- for index_config in indexes -%}
    {%- if index_config is mapping -%}
      {%- if index_config.get('unique', none) is not none -%}
        {{ risingwave__validation_report(
          'RW004',
          "`indexes[].unique` is a PostgreSQL adapter option and is ignored by dbt-risingwave. "
          ~ "Remove it from the `" ~ materialization ~ "` model index config."
        ) }}
      {%- endif -%}
      {%- if index_config.get('type', none) is not none -%}
        {{ risingwave__validation_report(
          'RW005',
          "`indexes[].type` is a PostgreSQL adapter option and is ignored by dbt-risingwave. "
          ~ "Remove it from the `" ~ materialization ~ "` model index config."
        ) }}
      {%- endif -%}
    {%- endif -%}
  {%- endfor -%}
{%- endmacro %}


{% macro risingwave__validate_model_sql(sql, materialization, wraps_model_sql=false) -%}
  {%- set normalized_sql = (sql | default('', true)) | trim | lower -%}

  {%- if wraps_model_sql and risingwave__looks_like_ddl(normalized_sql) -%}
    {{ risingwave__validation_report(
      'RW001',
      "`" ~ materialization ~ "` wraps model SQL in adapter-managed DDL, so the model SQL should "
      ~ "usually be a query expression rather than a full DDL statement. Use a raw-DDL "
      ~ "materialization such as `source`, `connection`, `secret`, `table_with_connector`, or raw `sink` "
      ~ "when the model needs to provide the complete RisingWave DDL."
    ) }}
  {%- endif -%}

  {%- if 'create materialized view' in normalized_sql and 'retention_seconds' in normalized_sql -%}
    {{ risingwave__validation_report(
      'RW002',
      "`retention_seconds` is not a supported option on `CREATE MATERIALIZED VIEW`. "
      ~ "Use `subscription` with `retention` for cross-database MV retention, or an append-only "
      ~ "`CREATE TABLE ... WITH (retention_seconds = ...)` when table storage TTL is intended."
    ) }}
  {%- endif -%}

  {%- if 'create subscription' in normalized_sql and 'retention_seconds' in normalized_sql -%}
    {{ risingwave__validation_report(
      'RW003',
      "`CREATE SUBSCRIPTION` uses `WITH (retention = ...)`, not `retention_seconds`."
    ) }}
  {%- endif -%}

  {%- if config.get('retention_seconds', none) is not none -%}
    {{ risingwave__validation_report(
      'RW006',
      "`retention_seconds` is not rendered from dbt model config by dbt-risingwave. "
      ~ "Put it in a raw RisingWave `CREATE TABLE ... WITH (...)` statement when table storage TTL is intended."
    ) }}
  {%- endif -%}

  {%- if materialization != 'subscription' and config.get('retention', none) is not none -%}
    {{ risingwave__validation_report(
      'RW007',
      "`retention` is only used by the `subscription` materialization. It is ignored by `"
      ~ materialization ~ "`."
    ) }}
  {%- endif -%}

  {%- if materialization != 'subscription' and config.get('subscription_options', none) is not none -%}
    {{ risingwave__validation_report(
      'RW008',
      "`subscription_options` is only used by the `subscription` materialization. It is ignored by `"
      ~ materialization ~ "`."
    ) }}
  {%- endif -%}

  {%- if materialization not in ['materialized_view', 'view'] and config.get('zero_downtime', none) is not none -%}
    {{ risingwave__validation_report(
      'RW009',
      "`zero_downtime` is only supported by the `materialized_view` and `view` materializations. "
      ~ "It is ignored by `" ~ materialization ~ "`."
    ) }}
  {%- endif -%}

  {{ risingwave__validate_ignored_index_options(materialization) }}
{%- endmacro %}
