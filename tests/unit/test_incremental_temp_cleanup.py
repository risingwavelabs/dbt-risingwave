import re
from types import SimpleNamespace

from dbt.adapters.risingwave.relation import RisingWaveRelation

from tests.unit.test_materialization_relation_lookup import render_adapter_macro


def test_stale_temp_tables_of_the_same_model_are_dropped():
    temp_relation = RisingWaveRelation.create(
        database="dev",
        schema="analytics",
        identifier="orders__dbt_tmp152422218221",
        type="table",
    )
    catalog_tables = [
        "orders__dbt_tmp152421038004",
        "orders__dbt_tmp152422218221",
        "orders__dbt_tmp",
        "orders__dbt_tmp_backup",
        "orders__dbt_tmp1x",
    ]
    executed = []

    def statement(name, fetch_result=False, caller=None):
        executed.append((name, " ".join(caller().split())))
        return ""

    render_adapter_macro(
        "risingwave__drop_stale_temp_tables",
        {},
        temp_relation,
        extra_context={
            "modules": SimpleNamespace(re=re),
            "statement": statement,
            "load_result": lambda name: SimpleNamespace(
                table=SimpleNamespace(rows=[[name] for name in catalog_tables])
            ),
            "log": lambda *args, **kwargs: "",
        },
    )

    listing = [sql for name, sql in executed if name == "list_stale_temp_tables"]
    assert len(listing) == 1
    assert "rw_schemas.name = 'analytics'" in listing[0]
    assert "starts_with(rw_tables.name, 'orders__dbt_tmp')" in listing[0]
    assert [sql for name, sql in executed if name == "drop_stale_temp_table"] == [
        'drop table if exists "dev"."analytics"."orders__dbt_tmp152421038004"'
    ]
