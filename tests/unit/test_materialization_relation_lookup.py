import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace


MATERIALIZATION_DIR = (
    Path(__file__).resolve().parents[2]
    / "dbt"
    / "include"
    / "risingwave"
    / "macros"
    / "materializations"
)
ADAPTER_MACROS = MATERIALIZATION_DIR.parent / "adapters.sql"
VALIDATION_MACROS = MATERIALIZATION_DIR.parent / "validation.sql"
CONNECTIONS = MATERIALIZATION_DIR.parents[3] / "adapters" / "risingwave" / "connections.py"

NATIVE_MODEL_SESSION_SETTINGS = {
    "streaming_parallelism",
    "streaming_parallelism_for_backfill",
    "streaming_max_parallelism",
    "enable_serverless_backfill",
    "backfill_rate_limit",
    "source_rate_limit",
    "sink_rate_limit",
    "streaming_parallelism_for_materialized_view",
    "streaming_parallelism_for_source",
    "streaming_parallelism_for_table",
    "streaming_parallelism_for_sink",
    "streaming_parallelism_for_index",
    "enable_index_selection",
}


def test_connector_materializations_use_catalog_relation_lookup():
    for filename in ("table_with_connector.sql", "sink.sql", "source.sql", "subscription.sql"):
        materialization = (MATERIALIZATION_DIR / filename).read_text()

        assert "risingwave__get_relation_without_caching(target_relation)" in materialization
        assert "adapter.get_relation" not in materialization


def test_connector_materializations_apply_grants():
    for filename in ("table_with_connector.sql", "sink.sql", "source.sql", "subscription.sql"):
        materialization = (MATERIALIZATION_DIR / filename).read_text()

        assert 'config.get("grants")' in materialization
        assert "should_revoke(existing_relation=old_relation" in materialization
        assert "apply_grants(target_relation, grant_config" in materialization


def test_secret_materialization_uses_secret_catalog_lifecycle():
    materialization = (MATERIALIZATION_DIR / "secret.sql").read_text()

    assert "type='secret'" in materialization
    assert "rw_catalog.rw_secrets" in materialization
    assert "rw_catalog.rw_schemas" in materialization
    assert "drop secret if exists {{ target_relation }} cascade" in materialization
    assert "risingwave__run_sql(sql)" in materialization
    assert 'config.get("grants")' in materialization
    assert "apply_grants(target_relation, grant_config" in materialization
    assert "adapter.get_relation" not in materialization


def test_secret_grants_use_secret_catalog_and_usage_privilege():
    grants = (MATERIALIZATION_DIR / "grants.sql").read_text()
    adapter_macros = ADAPTER_MACROS.read_text()

    assert "relation.type == 'secret'" in grants
    assert "rw_catalog.rw_secrets" in grants
    assert "then 'usage'" in grants
    assert "relation.type == 'secret' %} secret" in grants
    assert "drop secret if exists {{ relation }} cascade" in adapter_macros


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


def test_native_session_model_configs_are_allowlisted():
    adapter_macros = ADAPTER_MACROS.read_text()

    for setting in NATIVE_MODEL_SESSION_SETTINGS:
        assert f'"{setting}"' in adapter_macros

    assert 'config.get("background_ddl", none)' in adapter_macros
    assert "risingwave__native_model_session_settings()" in adapter_macros
    assert "set database" not in adapter_macros.lower()


def test_adapter_validation_rules_are_documented_in_macro():
    validation_macros = VALIDATION_MACROS.read_text()

    assert "risingwave_adapter_validation" in validation_macros
    assert "`retention_seconds` is not a supported option on `CREATE MATERIALIZED VIEW`" in validation_macros
    assert "`CREATE SUBSCRIPTION` uses `WITH (retention = ...)`" in validation_macros
    assert "`indexes[].unique` is a PostgreSQL adapter option" in validation_macros
    assert "`indexes[].type` is a PostgreSQL adapter option" in validation_macros
    assert "`zero_downtime` is only supported" in validation_macros
    assert "RW001" in validation_macros
    assert "RW009" in validation_macros


def test_adapter_validation_is_wired_into_materializations():
    expected_calls = {
        "materialized_view.sql": "risingwave__validate_model_sql(sql, 'materialized_view', true)",
        "materializedview.sql": "risingwave__validate_model_sql(sql, 'materializedview', true)",
        "table.sql": "risingwave__validate_model_sql(sql, 'table', true)",
        "view.sql": "risingwave__validate_model_sql(sql, 'view', true)",
        "incremental.sql": "risingwave__validate_model_sql(sql, 'incremental', true)",
        "subscription.sql": 'risingwave__validate_model_sql(sql, "subscription", true)',
        "source.sql": 'risingwave__validate_model_sql(sql, "source", false)',
        "table_with_connector.sql": 'risingwave__validate_model_sql(sql, "table_with_connector", false)',
        "connection.sql": "risingwave__validate_model_sql(sql, 'connection', false)",
        "secret.sql": "risingwave__validate_model_sql(sql, 'secret', false)",
    }

    for filename, expected_call in expected_calls.items():
        materialization = (MATERIALIZATION_DIR / filename).read_text()
        assert expected_call in materialization

    sink = (MATERIALIZATION_DIR / "sink.sql").read_text()
    assert 'config.get("connector")' in sink
    assert 'risingwave__validate_model_sql(sql, "sink", connector is not none)' in sink


def test_zero_downtime_immediate_cleanup_is_dependency_safe():
    materialized_view = (MATERIALIZATION_DIR / "materialized_view.sql").read_text()
    view = (MATERIALIZATION_DIR / "view.sql").read_text()
    adapter_macros = ADAPTER_MACROS.read_text()

    for materialization in (materialized_view, view):
        assert "risingwave__drop_zero_downtime_temp_relation(temp_relation)" in materialization
        assert "risingwave__drop_relation(temp_relation)" not in materialization

    assert "rw_catalog.rw_depend" in adapter_macros
    assert (
        "Preserving zero-downtime temporary relation because dependent objects still reference it"
        in adapter_macros
    )
    assert "drop materialized view if exists {{ relation }}" in adapter_macros
    assert "drop view if exists {{ relation }}" in adapter_macros
    assert "DROP MATERIALIZED VIEW IF EXISTS {{ obj_relation }} CASCADE" not in adapter_macros
    assert "DROP VIEW IF EXISTS {{ obj_relation }} CASCADE" not in adapter_macros


def test_profile_session_settings_are_allowlisted():
    connections = load_local_connections_module()

    assert set(connections.RISINGWAVE_PROFILE_SESSION_SETTINGS) == NATIVE_MODEL_SESSION_SETTINGS
    assert "background_ddl" not in connections.RISINGWAVE_PROFILE_SESSION_SETTINGS


def test_profile_session_settings_render_safe_set_statements():
    connections = load_local_connections_module()

    class FakeCursor:
        def __init__(self):
            self.statements = []
            self.closed = False

        def execute(self, sql):
            self.statements.append(sql)

        def close(self):
            self.closed = True

    class FakeHandle:
        def __init__(self):
            self.cursor_obj = FakeCursor()

        def cursor(self):
            return self.cursor_obj

    handle = FakeHandle()
    credentials = SimpleNamespace(
        streaming_parallelism_for_materialized_view="bounded(16)",
        streaming_parallelism_for_source="ratio(0.5)",
        backfill_rate_limit=1000,
        enable_serverless_backfill=True,
        enable_index_selection=False,
    )

    connections.RisingWaveConnectionManager._configure_session(handle, credentials)

    assert handle.cursor_obj.closed
    assert handle.cursor_obj.statements == [
        "SET RW_IMPLICIT_FLUSH TO true",
        "SET enable_serverless_backfill = true",
        "SET backfill_rate_limit = 1000",
        "SET streaming_parallelism_for_materialized_view = 'bounded(16)'",
        "SET streaming_parallelism_for_source = 'ratio(0.5)'",
        "SET enable_index_selection = false",
    ]


def load_local_connections_module():
    module_name = "local_risingwave_connections"
    spec = importlib.util.spec_from_file_location(module_name, CONNECTIONS)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module
