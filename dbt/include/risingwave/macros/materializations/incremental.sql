{% materialization incremental, adapter='risingwave' %}
  {{ exceptions.raise_compiler_error(
      """
        dbt-risingwave does not support incremental models, but we provide a `materializedview` model 
        which could keep your data up-to-date automatically and incrementally.

        Use the `materializedview` instead.
      """
  )}}
{% endmaterialization %}
