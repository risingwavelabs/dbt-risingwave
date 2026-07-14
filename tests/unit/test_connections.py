import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, call


CONNECTIONS = (
    Path(__file__).resolve().parents[2]
    / "dbt"
    / "adapters"
    / "risingwave"
    / "connections.py"
)


def test_cancel_quotes_compound_process_id_with_query_binding():
    connections = load_local_connections_module()
    manager = connections.RisingWaveConnectionManager.__new__(
        connections.RisingWaveConnectionManager
    )
    process_cursor = SimpleNamespace(
        fetchall=lambda: [
            (
                "2:1806",
                "root",
                "127.0.0.1",
                "dev",
                "1 second",
                'CREATE MATERIALIZED VIEW "dev"."public"."my_model" AS SELECT 1',
            )
        ]
    )
    manager.add_query = Mock(side_effect=[(None, process_cursor), (None, None)])
    connection = SimpleNamespace(
        name="model.project.my_model",
        credentials=SimpleNamespace(database="dev", schema="public"),
    )

    manager.cancel(connection)

    assert manager.add_query.call_args_list == [
        call("SHOW PROCESSLIST"),
        call("KILL %s", bindings=("2:1806",)),
    ]


def load_local_connections_module():
    module_name = "local_risingwave_connections_for_cancel_tests"
    spec = importlib.util.spec_from_file_location(module_name, CONNECTIONS)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module
