from pathlib import Path


MATERIALIZATION_DIR = (
    Path(__file__).resolve().parents[2]
    / "dbt"
    / "include"
    / "risingwave"
    / "macros"
    / "materializations"
)
ADAPTER_MACROS = MATERIALIZATION_DIR.parent / "adapters.sql"


def test_connector_materializations_use_catalog_relation_lookup():
    for filename in ("table_with_connector.sql", "sink.sql", "source.sql", "subscription.sql"):
        materialization = (MATERIALIZATION_DIR / filename).read_text()

        assert "risingwave__get_relation_without_caching(target_relation)" in materialization
        assert "adapter.get_relation" not in materialization


def test_subscription_materialization_stays_in_current_database():
    materialization = (MATERIALIZATION_DIR / "subscription.sql").read_text()
    adapter_macros = ADAPTER_MACROS.read_text()

    assert "set database" not in materialization.lower()
    assert "set database" not in adapter_macros.lower()
    assert "risingwave__create_subscription(target_relation, sql)" in materialization
    assert "sql | trim" in adapter_macros
    assert 'config.get("subscription_source"' not in adapter_macros
    assert 'config.get("relation"' not in adapter_macros
    assert 'config.get("from"' not in adapter_macros
    assert 'config.get("from_name"' not in adapter_macros
    assert 'config.get("from_schema"' not in adapter_macros
