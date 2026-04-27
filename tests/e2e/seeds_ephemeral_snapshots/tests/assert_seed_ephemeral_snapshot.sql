with failures as (
    select 'seed_users should contain the seeded rows' as failure
    where (
        select count(*)
        from {{ target.schema }}.seed_users
    ) != 3

    union all

    select 'active_user_summary should materialize the ephemeral model output' as failure
    where not exists (
        select 1
        from {{ target.schema }}.active_user_summary
        where id = 1
          and name_upper = 'ALICE'
    )

    union all

    select 'active_user_summary should not include inactive users after the initial run' as failure
    where exists (
        select 1
        from {{ target.schema }}.active_user_summary
        where id = 3
    )

    union all

    select 'ephemeral_active_users should not be created as a relation' as failure
    where exists (
        select 1
        from rw_catalog.rw_relations
        join rw_catalog.rw_schemas on schema_id = rw_schemas.id
        where rw_schemas.name = '{{ target.schema }}'
          and rw_relations.name = 'ephemeral_active_users'
    )

    union all

    select 'snapshot should contain the initial seeded rows' as failure
    where (
        select count(*)
        from {{ target.schema }}.seed_users_snapshot
    ) != 3

    union all

    select 'snapshot should have current rows for all seeded users' as failure
    where (
        select count(*)
        from {{ target.schema }}.seed_users_snapshot
        where dbt_valid_to is null
    ) != 3
)
select * from failures
