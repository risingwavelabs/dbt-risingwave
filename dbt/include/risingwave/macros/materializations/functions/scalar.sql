{% macro risingwave__scalar_function_sql(target_relation) %}
    CREATE FUNCTION IF NOT EXISTS {{ target_relation.render() }} ({{ formatted_scalar_function_args_sql() }})
    RETURNS {{ model.returns.data_type }}
    {{ scalar_function_volatility_sql() }}
    LANGUAGE SQL
    AS
    $$
       {{ model.compiled_code }}
    $$;
{% endmacro %}

{% macro risingwave__scalar_function_javascript(target_relation) %}
    {% set options = [] %}
    {% if model.config.get('async') %}
        {% do options.append('async = true') %}
    {% endif %}
    {% if model.config.get('batch') %}
        {% do options.append('batch = true') %}
    {% endif %}
    {% if model.config.get('always_retry_on_network_error') %}
        {% do options.append('always_retry_on_network_error = true') %}
    {% endif %}

    CREATE FUNCTION IF NOT EXISTS {{ target_relation.render() }} ({{ formatted_scalar_function_args_sql() }})
    RETURNS {{ model.returns.data_type }}
    {{ scalar_function_volatility_sql() }}
    LANGUAGE JAVASCRIPT
    AS
    $$
       {{ model.compiled_code }}
    $$
    {%- if options | length > 0 %}
    WITH ({{ options | join(', ') }})
    {%- endif %};
{% endmacro %}

{% macro risingwave__scalar_function_python(target_relation) %}
    {% set link = model.config.get('link') %}
    {% if not link %}
        {{ exceptions.raise_compiler_error("RisingWave external Python UDFs require `config.link`.") }}
    {% endif %}
    {% set remote_name = model.config.get('remote_name', model.name) %}
    {% set options = [] %}
    {% if model.config.get('always_retry_on_network_error') %}
        {% do options.append('always_retry_on_network_error = true') %}
    {% endif %}

    CREATE FUNCTION IF NOT EXISTS {{ target_relation.render() }} ({{ formatted_scalar_function_args_sql() }})
    RETURNS {{ model.returns.data_type }}
    {{ scalar_function_volatility_sql() }}
    AS '{{ remote_name | replace("'", "''") }}'
    USING LINK '{{ link | replace("'", "''") }}'
    {%- if options | length > 0 %}
    WITH ({{ options | join(', ') }})
    {%- endif %};
{% endmacro %}
