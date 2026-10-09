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


PROCESSLIST_DESCRIPTION = [
    (name,) for name in ("Worker Id", "Id", "User", "Host", "Database", "Time", "Info")
]


class FakeProcessListCursor:
    def __init__(self, rows):
        self.description = PROCESSLIST_DESCRIPTION
        self.rows = rows
        self.executed = []

    def execute(self, sql):
        self.executed.append(sql)

    def fetchall(self):
        return self.rows

    def close(self):
        pass


def processlist_row(process_id, info):
    worker_id = process_id.split(":")[0]
    return (worker_id, process_id, "root", "127.0.0.1:5000", "dev", "10ms", info)


def make_cancel_manager(connections, *add_query_results):
    manager = connections.RisingWaveConnectionManager.__new__(
        connections.RisingWaveConnectionManager
    )
    manager.add_query = Mock(side_effect=list(add_query_results))
    return manager


def make_connection(backend_pid, remembered_session=None):
    connection = SimpleNamespace(
        name="model.project.my_model",
        handle=SimpleNamespace(get_backend_pid=lambda: backend_pid),
    )
    if remembered_session is not None:
        setattr(connection, "_risingwave_session_process_id", remembered_session)
    return connection


def test_open_remembers_full_process_id_of_own_session():
    connections = load_local_connections_module()

    class FakeHandle:
        def __init__(self, cursor):
            self._cursor = cursor

        def get_backend_pid(self):
            return 79

        def cursor(self):
            return self._cursor

    cursor = FakeProcessListCursor(
        [
            # Another frontend can reuse the same process id.
            processlist_row("3:79", 'CREATE MATERIALIZED VIEW "dev"."public"."other" AS SELECT 1'),
            processlist_row("3:80", "SHOW PROCESSLIST"),
            processlist_row("2:79", "SHOW PROCESSLIST"),
        ]
    )
    connection = SimpleNamespace(handle=FakeHandle(cursor))

    with patch.object(connections.psycopg2.extensions, "connection", FakeHandle):
        connections.RisingWaveConnectionManager._remember_session_process_id(connection)

    assert cursor.executed == ["SHOW PROCESSLIST"]
    assert connection._risingwave_session_process_id == (79, "2:79")


def test_cancel_kills_remembered_session_with_query_binding():
    connections = load_local_connections_module()
    manager = make_cancel_manager(connections, (None, None))

    manager.cancel(make_connection(79, remembered_session=(79, "3:79")))

    assert manager.add_query.call_args_list == [call("KILL %s", bindings=("3:79",))]


def test_cancel_falls_back_to_process_id_column_on_single_frontend():
    connections = load_local_connections_module()
    processlist = FakeProcessListCursor(
        [
            processlist_row("2:1806", 'CREATE MATERIALIZED VIEW "dev"."custom"."alias" AS SELECT 1'),
            processlist_row("2:1807", "SHOW PROCESSLIST"),
        ]
    )
    manager = make_cancel_manager(connections, (None, processlist), (None, None))

    manager.cancel(make_connection(1806))

    # The first column is the worker id; KILL needs the `<worker>:<process>` id.
    assert manager.add_query.call_args_list == [
        call("SHOW PROCESSLIST"),
        call("KILL %s", bindings=("2:1806",)),
    ]


def test_cancel_skips_process_id_that_is_ambiguous_across_frontends():
    connections = load_local_connections_module()
    processlist = FakeProcessListCursor(
        [
            processlist_row("2:1806", "SELECT 1"),
            processlist_row("3:1806", "SELECT 2"),
        ]
    )
    manager = make_cancel_manager(connections, (None, processlist))

    manager.cancel(make_connection(1806))

    assert manager.add_query.call_args_list == [call("SHOW PROCESSLIST")]


def test_cancel_does_not_raise_when_kill_fails():
    connections = load_local_connections_module()
    manager = make_cancel_manager(connections, RuntimeError("Session not found"))

    manager.cancel(make_connection(79, remembered_session=(79, "2:79")))

    assert manager.add_query.call_args_list == [call("KILL %s", bindings=("2:79",))]


def load_local_connections_module():
    module_name = "local_risingwave_connections_for_cancel_tests"
    spec = importlib.util.spec_from_file_location(module_name, CONNECTIONS)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module
