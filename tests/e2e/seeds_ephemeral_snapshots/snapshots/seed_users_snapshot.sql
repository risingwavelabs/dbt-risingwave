{% snapshot seed_users_snapshot %}

{{
    config(
        target_schema=target.schema,
        unique_key='id',
        strategy='check',
        check_cols=['name', 'status']
    )
}}

select
    id,
    name,
    status
from {{ ref('seed_users') }}

{% endsnapshot %}
