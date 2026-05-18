from pathlib import Path


MATERIALIZATION_DIR = (
    Path(__file__).resolve().parents[2]
    / "dbt"
    / "include"
    / "risingwave"
    / "macros"
    / "materializations"
)


def test_connector_materializations_use_catalog_relation_lookup():
    for filename in ("table_with_connector.sql", "sink.sql", "source.sql"):
        materialization = (MATERIALIZATION_DIR / filename).read_text()

        assert "risingwave__get_relation_without_caching(target_relation)" in materialization
        assert "adapter.get_relation" not in materialization
