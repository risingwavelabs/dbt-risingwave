from dataclasses import dataclass
from typing import Any, Dict, List, NamedTuple, Optional

import psycopg2
from dbt.adapters.contracts.connection import Connection
from dbt.adapters.events.logging import AdapterLogger
from dbt.adapters.postgres.connections import (
    PostgresConnectionManager,
    PostgresCredentials,
)
from dbt.adapters.postgres.record import PostgresRecordReplayHandle
from dbt_common.record import RecorderMode, get_record_mode_from_env

logger = AdapterLogger("RisingWave")


RISINGWAVE_PROFILE_SESSION_SETTINGS = (
    "streaming_parallelism",
    "streaming_parallelism_for_backfill",
    "streaming_max_parallelism",
    "streaming_cache_refill_policy",
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
)

SESSION_PROCESS_ID_ATTR = "_risingwave_session_process_id"


class _ProcessListEntry(NamedTuple):
    process_id: str
    worker_id: Optional[str]
    session_pid: Optional[int]
    info: str


def _parse_processlist(description, rows) -> List[_ProcessListEntry]:
    """Parse `SHOW PROCESSLIST` rows by column name.

    RisingWave returns `Worker Id, Id, User, Host, Database, Time, Info`, where
    `Id` is the `<worker id>:<process id>` string accepted by `KILL`.
    """
    names = [str(column[0]).lower() for column in (description or [])]
    id_index = names.index("id") if "id" in names else 0
    info_index = names.index("info") if "info" in names else -1

    entries = []
    for row in rows:
        process_id = row[id_index]
        if process_id is None or str(process_id) == "":
            # Placeholder rows report frontends whose process list is unavailable.
            continue
        process_id = str(process_id)
        worker_id, _, session_pid = process_id.rpartition(":")
        try:
            parsed_session_pid: Optional[int] = int(session_pid)
        except ValueError:
            parsed_session_pid = None
        entries.append(
            _ProcessListEntry(
                process_id=process_id,
                worker_id=worker_id or None,
                session_pid=parsed_session_pid,
                info=str(row[info_index] or ""),
            )
        )
    return entries


@dataclass
class RisingWaveCredentials(PostgresCredentials):
    """
    according to https://github.com/risingwavelabs/risingwave/blob/1193d5370e619a2dfae385b695941754ae63d04e/src/common/src/session_config/mod.rs#L271
    & https://github.com/dbt-labs/dbt-core/blob/b2ea2b8b256e5db1da0b712dfedd7973e1e50a37/plugins/postgres/dbt/adapters/postgres/connections.py#L20
    """

    streaming_parallelism: Optional[Any] = None
    streaming_parallelism_for_backfill: Optional[Any] = None
    streaming_max_parallelism: Optional[Any] = None
    streaming_cache_refill_policy: Optional[str] = None
    enable_serverless_backfill: Optional[bool] = None
    backfill_rate_limit: Optional[int] = None
    source_rate_limit: Optional[int] = None
    sink_rate_limit: Optional[int] = None
    streaming_parallelism_for_materialized_view: Optional[Any] = None
    streaming_parallelism_for_source: Optional[Any] = None
    streaming_parallelism_for_table: Optional[Any] = None
    streaming_parallelism_for_sink: Optional[Any] = None
    streaming_parallelism_for_index: Optional[Any] = None
    enable_index_selection: Optional[bool] = None

    @property
    def type(self):
        return "risingwave"

    @property
    def unique_field(self):
        return self.host

    def _connection_keys(self):
        return (
            "host",
            "port",
            "user",
            "database",
            "schema",
            "cluster",
            "sslmode",
            "keepalives_idle",
            "connect_timeout",
            "autocommit",
            "retries",
        )


class RisingWaveConnectionManager(PostgresConnectionManager):
    TYPE = "risingwave"

    @classmethod
    def _super_open(cls, connection, extra_kwargs: Optional[Dict[str, str]] = None):
        """Copied from upstream repo."""

        if connection.state == "open":
            logger.debug("Connection is already open, skipping open.")
            return connection

        credentials = cls.get_credentials(connection.credentials)
        kwargs = {}
        # we don't want to pass 0 along to connect() as postgres will try to
        # call an invalid setsockopt() call (contrary to the docs).
        if credentials.keepalives_idle:
            kwargs["keepalives_idle"] = credentials.keepalives_idle

        # psycopg2 doesn't support search_path officially,
        # see https://github.com/psycopg/psycopg2/issues/465
        search_path = credentials.search_path
        if search_path is not None and search_path != "":
            # see https://postgresql.org/docs/9.5/libpq-connect.html
            kwargs["options"] = "-c search_path={}".format(search_path.replace(" ", "\\ "))

        if credentials.sslmode:
            kwargs["sslmode"] = credentials.sslmode

        if credentials.sslcert is not None:
            kwargs["sslcert"] = credentials.sslcert

        if credentials.sslkey is not None:
            kwargs["sslkey"] = credentials.sslkey

        if credentials.sslrootcert is not None:
            kwargs["sslrootcert"] = credentials.sslrootcert

        if credentials.application_name:
            kwargs["application_name"] = credentials.application_name

        # RisingWave specific
        kwargs.update(extra_kwargs or {})

        def connect():
            handle = None

            # Keep this in sync with PostgresConnectionManager.open. Replay
            # mode does not create a real database connection, while record
            # and diff modes wrap one to observe native connection activity.
            rec_mode = get_record_mode_from_env()
            if rec_mode != RecorderMode.REPLAY:
                handle = psycopg2.connect(
                    dbname=credentials.database,
                    user=credentials.user,
                    host=credentials.host,
                    password=credentials.password,
                    port=credentials.port,
                    connect_timeout=credentials.connect_timeout,
                    **kwargs,
                )

            if handle is not None and credentials.autocommit:
                handle.autocommit = True

            if rec_mode is not None:
                handle = PostgresRecordReplayHandle(handle, connection)

            if credentials.role:
                handle.cursor().execute("set role {}".format(credentials.role))
            return handle

        retryable_exceptions = [
            # OperationalError is subclassed by all psycopg2 Connection Exceptions and it's raised
            # by generic connection timeouts without an error code. This is a limitation of
            # psycopg2 which doesn't provide subclasses for errors without a SQLSTATE error code.
            # The limitation has been known for a while and there are no efforts to tackle it.
            # See: https://github.com/psycopg/psycopg2/issues/682
            psycopg2.errors.OperationalError,
        ]

        def exponential_backoff(attempt: int):
            return attempt * attempt

        return cls.retry_connection(
            connection,
            connect=connect,
            logger=logger,
            retry_limit=credentials.retries,
            retry_timeout=exponential_backoff,
            retryable_exceptions=retryable_exceptions,
        )

    @classmethod
    def open(cls, connection):
        # todo: extending PostgresConnectionManager does not allow
        # us to pass custom params to psycopg2.connect
        connection = cls._super_open(
            connection,
            extra_kwargs={
                "gssencmode": "disable"  # see https://github.com/risingwavelabs/risingwave/issues/12124
            },
        )
        credentials = cls.get_credentials(connection.credentials)
        cls._configure_session(connection.handle, credentials)
        cls._remember_session_process_id(connection)
        return connection

    @staticmethod
    def _configure_session(handle, credentials: RisingWaveCredentials):
        if handle is None or credentials is None:
            return

        cursor = handle.cursor()
        try:
            cursor.execute("SET RW_IMPLICIT_FLUSH TO true")
            for setting in RISINGWAVE_PROFILE_SESSION_SETTINGS:
                value = getattr(credentials, setting, None)
                if value is not None:
                    cursor.execute(
                        f"SET {setting} = {RisingWaveConnectionManager._format_session_value(value)}"
                    )
        finally:
            cursor.close()

    @staticmethod
    def _format_session_value(value: Any) -> str:
        if isinstance(value, bool):
            return str(value).lower()
        if isinstance(value, (int, float)):
            return str(value)

        value_str = str(value)
        if value_str.lower() in {"default", "adaptive"}:
            return value_str
        return "'" + value_str.replace("'", "''") + "'"

    @staticmethod
    def _remember_session_process_id(connection) -> None:
        """Record the `SHOW PROCESSLIST` id of the session behind this connection.

        RisingWave identifies a session as `<worker id>:<process id>`, and process
        ids are only unique within one frontend. Resolving the full id while the
        session is idle lets `cancel()` kill exactly this session later, even in
        multi-frontend clusters.
        """
        handle = connection.handle
        session = None
        if isinstance(handle, psycopg2.extensions.connection):
            try:
                backend_pid = handle.get_backend_pid()
                cursor = handle.cursor()
                try:
                    cursor.execute("SHOW PROCESSLIST")
                    entries = _parse_processlist(cursor.description, cursor.fetchall())
                finally:
                    cursor.close()
                own_entries = [
                    entry
                    for entry in entries
                    if entry.session_pid == backend_pid
                    and entry.info.lstrip().upper().startswith("SHOW PROCESSLIST")
                ]
                if len(own_entries) == 1:
                    session = (backend_pid, own_entries[0].process_id)
            except Exception as exc:
                logger.debug(f"Unable to resolve RisingWave process id: {exc}")
        setattr(connection, SESSION_PROCESS_ID_ATTR, session)

    def _session_process_id_for_cancel(self, connection: Connection) -> Optional[str]:
        try:
            backend_pid = connection.handle.get_backend_pid()
        except Exception as exc:
            logger.debug(f"Unable to read backend pid for '{connection.name}': {exc}")
            return None

        session = getattr(connection, SESSION_PROCESS_ID_ATTR, None)
        if session is not None and session[0] == backend_pid:
            return session[1]

        # Fallback when the id was not resolved at open time. A bare process id is
        # only unambiguous when the cluster has a single frontend.
        entries = self._read_processlist()
        if entries is None or len({entry.worker_id for entry in entries}) > 1:
            return None
        matches = [entry for entry in entries if entry.session_pid == backend_pid]
        return matches[0].process_id if len(matches) == 1 else None

    def _read_processlist(self) -> Optional[List[_ProcessListEntry]]:
        try:
            _, cursor = self.add_query("SHOW PROCESSLIST")
            return _parse_processlist(cursor.description, cursor.fetchall())
        except Exception as exc:
            logger.debug(f"Unable to read RisingWave process list: {exc}")
            return None

    def cancel(self, connection: Connection):
        connection_name = connection.name
        process_id = self._session_process_id_for_cancel(connection)
        if process_id is None:
            logger.debug(f"No RisingWave session found to cancel for '{connection_name}'")
            return

        logger.debug(f"Cancelling query '{connection_name}' ({process_id})")
        try:
            self.add_query("KILL %s", bindings=(process_id,))
        except Exception as exc:
            # Cancellation is best effort: dbt is already stopping because of an
            # earlier failure or interrupt, so a failed KILL must not replace that
            # outcome with a fatal error.
            logger.warning(
                f"Failed to cancel RisingWave query for '{connection_name}' ({process_id}): {exc}"
            )

    # Disable transactions.
    def add_begin_query(self, *args, **kwargs):
        pass

    def add_commit_query(self, *args, **kwargs):
        pass

    def begin(self):
        pass

    def commit(self):
        pass

    def clear_transaction(self):
        pass
