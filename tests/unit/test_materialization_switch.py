from types import SimpleNamespace

import pytest
from dbt.adapters.risingwave.relation import RisingWaveRelation

from tests.unit.test_materialization_relation_lookup import render_adapter_macro


def make_relation(relation_type, identifier="orders"):
    return RisingWaveRelation.create(
        database="dev",
        schema="analytics",
        identifier=identifier,
        type=relation_type,
    )


def replace_relation(old_relation, target_relation, dependents=(), has_connector=False):
    executed = []
    dropped = []

    def statement(name, fetch_result=False, caller=None):
        executed.append(" ".join(caller().split()))
        return ""

    result = render_adapter_macro(
        "risingwave__replace_relation_of_other_type",
        {},
        old_relation,
        target_relation,
        extra_context={
            "statement": statement,
            "log": lambda *args, **kwargs: "",
            "adapter": SimpleNamespace(cache_dropped=dropped.append),
            "risingwave__list_relation_dependents": lambda relation: list(dependents),
            "risingwave__table_has_connector": lambda relation: has_connector,
        },
    )
    return result, executed, dropped


def test_same_type_keeps_existing_relation():
    old_relation = make_relation("materializedview")

    result, executed, dropped = replace_relation(old_relation, make_relation("materialized_view"))

    assert result == old_relation
    assert executed == []
    assert dropped == []


@pytest.mark.parametrize(
    "old_type, target_type, expected_drop",
    [
        ("view", "materialized_view", 'drop view "dev"."analytics"."orders"'),
        ("materialized_view", "table", 'drop materialized view "dev"."analytics"."orders"'),
        ("table", "view", 'drop table "dev"."analytics"."orders"'),
    ],
)
def test_switch_drops_old_relation_without_cascade(old_type, target_type, expected_drop):
    old_relation = make_relation(old_type)

    result, executed, dropped = replace_relation(old_relation, make_relation(target_type))

    assert result is None
    assert executed == [expected_drop]
    assert dropped == [old_relation]


def test_switch_with_dependents_fails_without_dropping():
    with pytest.raises(ValueError) as error:
        replace_relation(
            make_relation("materialized_view"),
            make_relation("view"),
            dependents=["sink analytics.orders_sink", "view analytics.orders_report"],
        )

    message = str(error.value)
    assert "from a materialized view to a view" in message
    assert "sink analytics.orders_sink, view analytics.orders_report" in message


@pytest.mark.parametrize(
    "old_type, has_connector, description",
    [
        ("table", True, "table with a connector"),
        ("source", False, "source"),
        ("sink", False, "sink"),
    ],
)
def test_objects_holding_data_or_external_state_are_not_replaced(
    old_type, has_connector, description
):
    with pytest.raises(ValueError) as error:
        replace_relation(
            make_relation(old_type),
            make_relation("materialized_view"),
            has_connector=has_connector,
        )

    assert f"it already exists as a {description}" in str(error.value)
