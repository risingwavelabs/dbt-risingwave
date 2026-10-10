import re
from types import SimpleNamespace

import pytest

from tests.unit.test_materialization_relation_lookup import render_adapter_macro


def render_option_value(value):
    return render_adapter_macro(
        "risingwave__sink_option_value",
        {},
        "e2e.option",
        value,
        extra_context={"modules": SimpleNamespace(re=re)},
    ).strip()


@pytest.mark.parametrize(
    "value, rendered",
    [
        ("plain", "'plain'"),
        ("it's quoted", "'it''s quoted'"),
        (1000, "'1000'"),
        ({"secret": "kafka_password"}, "secret kafka_password"),
        ({"secret": "credentials.kafka_password"}, "secret credentials.kafka_password"),
    ],
)
def test_sink_option_values_are_escaped_or_reference_secrets(value, rendered):
    assert render_option_value(value) == rendered


@pytest.mark.parametrize(
    "value",
    [
        {"secret": "kafka_password; drop table orders"},
        {"secret": "a.b.c"},
        {"secret": 1},
        {"secret": "kafka_password", "as_file": True},
        {"name": "kafka_password"},
    ],
)
def test_invalid_secret_references_are_rejected(value):
    with pytest.raises(ValueError, match="Invalid value for sink option `e2e.option`"):
        render_option_value(value)
