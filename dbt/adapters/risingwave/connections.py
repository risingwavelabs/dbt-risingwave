from contextlib import contextmanager
from dataclasses import dataclass
import dbt.exceptions  # noqa
from dbt.adapters.base import Credentials
from dbt.adapters.postgres import PostgresConnectionManager, PostgresCredentials
from dbt.helper_types import Port
from dbt.adapters.sql import SQLConnectionManager as connection_cls
from dbt.events import AdapterLogger
from typing import Dict, Optional
import psycopg2

logger = AdapterLogger("RisingWave")


@dataclass
class RisingWaveCredentials(PostgresCredentials):
    """
    according to https://github.com/risingwavelabs/risingwave/blob/1193d5370e619a2dfae385b695941754ae63d04e/src/common/src/session_config/mod.rs#L271
    & https://github.com/dbt-labs/dbt-core/blob/b2ea2b8b256e5db1da0b712dfedd7973e1e50a37/plugins/postgres/dbt/adapters/postgres/connections.py#L20
    """

    # todo(siwei): append more config here
    streaming_parallelism: Optional[int] = None

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
            kwargs["options"] = "-c search_path={}".format(
                search_path.replace(" ", "\\ ")
            )

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
            handle = psycopg2.connect(
                dbname=credentials.database,
                user=credentials.user,
                host=credentials.host,
                password=credentials.password,
                port=credentials.port,
                connect_timeout=credentials.connect_timeout,
                **kwargs,
            )
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
        connection.handle.cursor().execute("SET RW_IMPLICIT_FLUSH TO true")
        return connection

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
