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
    CREATE FUNCTION IF NOT EXISTS {{ target_relation.render() }} ({{ formatted_scalar_function_args_sql() }})
    RETURNS {{ model.returns.data_type }}
    {{ scalar_function_volatility_sql() }}
    LANGUAGE JAVASCRIPT
    AS
    $$
       {{ model.compiled_code }}
    $$;
{% endmacro %}
