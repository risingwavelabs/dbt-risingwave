from contextlib import contextmanager
from dataclasses import dataclass
import dbt.exceptions # noqa
from dbt.adapters.base import Credentials
from dbt.adapters.postgres import PostgresConnectionManager, PostgresCredentials
from dbt.helper_types import Port
from dbt.adapters.sql import SQLConnectionManager as connection_cls
from typing import Optional
from dbt.logger import GLOBAL_LOGGER as logger
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
    def open(cls, connection):
        # todo: extending PostgresConnectionManager does not allow
        # us to pass custom params to psycopg2.connect
        connection = super().open(connection)
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
