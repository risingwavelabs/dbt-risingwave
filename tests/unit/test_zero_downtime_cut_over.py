from types import SimpleNamespace

import pytest
from dbt.adapters.risingwave.relation import RisingWaveRelation

from tests.unit.test_materialization_relation_lookup import render_adapter_macro


def make_relation(identifier, relation_type):
    return RisingWaveRelation.create(
        database="dev", schema="analytics", identifier=identifier, type=relation_type
    )


def cut_over(old_type, new_type):
    executed = []

    def statement(name, fetch_result=False, caller=None):
        executed.append((name, " ".join(caller().split())))
        return ""

    retired = render_adapter_macro(
        "risingwave__zero_downtime_cut_over",
        {},
        make_relation("orders", old_type),
        make_relation("orders_dbt_zero_down_tmp_1", new_type),
        make_relation("orders", new_type),
        extra_context={
            "statement": statement,
            "log": lambda *args, **kwargs: "",
            "api": SimpleNamespace(Relation=RisingWaveRelation),
            "risingwave__swap_views": lambda old, new: f"swap views {old.identifier}",
            "risingwave__swap_materialized_views": lambda old, new: f"swap mvs {old.identifier}",
        },
    )
    return retired, executed


@pytest.mark.parametrize(
    "relation_type, swap_sql",
    [("view", "swap views orders"), ("materialized_view", "swap mvs orders")],
)
def test_same_type_cut_over_swaps(relation_type, swap_sql):
    retired, executed = cut_over(relation_type, relation_type)

    assert executed == [("swap", swap_sql)]
    assert retired.identifier == "orders_dbt_zero_down_tmp_1"


@pytest.mark.parametrize(
    "old_type, new_type, retire_sql, promote_sql",
    [
        (
            "view",
            "materialized_view",
            'alter view "dev"."analytics"."orders" rename to "orders_dbt_zero_down_tmp_1_old"',
            'alter materialized view "dev"."analytics"."orders_dbt_zero_down_tmp_1"'
            ' rename to "orders"',
        ),
        (
            "materialized_view",
            "view",
            'alter materialized view "dev"."analytics"."orders"'
            ' rename to "orders_dbt_zero_down_tmp_1_old"',
            'alter view "dev"."analytics"."orders_dbt_zero_down_tmp_1" rename to "orders"',
        ),
    ],
)
def test_switching_between_view_and_mv_renames_instead_of_swapping(
    old_type, new_type, retire_sql, promote_sql
):
    retired, executed = cut_over(old_type, new_type)

    assert executed == [
        ("retire_old_relation", retire_sql),
        ("promote_new_relation", promote_sql),
    ]
    assert retired.identifier == "orders_dbt_zero_down_tmp_1_old"
    assert retired.type == old_type


def test_zero_downtime_rejects_relations_other_than_views_and_mvs():
    with pytest.raises(ValueError, match="it exists as a table"):
        render_adapter_macro(
            "risingwave__check_zero_downtime_relation",
            {},
            make_relation("orders", "table"),
            make_relation("orders", "materialized_view"),
        )
