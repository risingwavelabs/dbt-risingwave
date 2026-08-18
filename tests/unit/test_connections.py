import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, call, patch


CONNECTIONS = (
    Path(__file__).resolve().parents[2]
    / "dbt"
    / "adapters"
    / "risingwave"
    / "connections.py"
)


def test_open_passes_risingwave_options_and_enables_autocommit():
    connections = load_local_connections_module()
    credentials = connections.RisingWaveCredentials.from_dict(
        {
            "host": "127.0.0.1",
            "user": "root",
            "password": "",
            "port": 4566,
            "dbname": "dev",
            "schema": "public",
            "autocommit": True,
        }
    )
    connection = SimpleNamespace(state="init", credentials=credentials, handle=None)
    handle = SimpleNamespace(autocommit=False)

    def retry_connection(connection, connect, **kwargs):
        connection.handle = connect()
        connection.state = "open"
        return connection

    with (
        patch.object(connections, "get_record_mode_from_env", return_value=None),
        patch.object(connections.psycopg2, "connect", return_value=handle) as connect,
        patch.object(
            connections.RisingWaveConnectionManager,
            "retry_connection",
            side_effect=retry_connection,
        ),
    ):
        result = connections.RisingWaveConnectionManager._super_open(
            connection, extra_kwargs={"gssencmode": "disable"}
        )

    assert result is connection
    assert handle.autocommit is True
    assert "autocommit" in credentials._connection_keys()
    connect.assert_called_once_with(
        dbname="dev",
        user="root",
        host="127.0.0.1",
        password="",
        port=4566,
        connect_timeout=10,
        application_name="dbt",
        gssencmode="disable",
    )


def test_open_uses_record_replay_handle_without_real_connection():
    connections = load_local_connections_module()
    credentials = connections.RisingWaveCredentials.from_dict(
        {
            "host": "127.0.0.1",
            "user": "root",
            "password": "",
            "port": 4566,
            "dbname": "dev",
            "schema": "public",
        }
    )
    connection = SimpleNamespace(state="init", credentials=credentials, handle=None)
    replay_handle = object()

    def retry_connection(connection, connect, **kwargs):
        connection.handle = connect()
        connection.state = "open"
        return connection

    with (
        patch.object(
            connections,
            "get_record_mode_from_env",
            return_value=connections.RecorderMode.REPLAY,
        ),
        patch.object(connections.psycopg2, "connect") as connect,
        patch.object(
            connections,
            "PostgresRecordReplayHandle",
            return_value=replay_handle,
        ) as record_replay_handle,
        patch.object(
            connections.RisingWaveConnectionManager,
            "retry_connection",
            side_effect=retry_connection,
        ),
    ):
        result = connections.RisingWaveConnectionManager._super_open(connection)

    assert result.handle is replay_handle
    connect.assert_not_called()
    record_replay_handle.assert_called_once_with(None, connection)


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
