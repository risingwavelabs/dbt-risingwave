import time

from dbt.adapters.base.meta import available
from dbt.adapters.postgres.impl import PostgresAdapter

from dbt.adapters.risingwave.connections import RisingWaveConnectionManager
from dbt.adapters.risingwave.relation import RisingWaveRelation


class RisingWaveAdapter(PostgresAdapter):
    ConnectionManager = RisingWaveConnectionManager
    Relation = RisingWaveRelation

    def _link_cached_relations(self, manifest):
        # lack of `pg_depend`, `pg_rewrite`
        pass

    @available
    @classmethod
    def sleep(cls, seconds):
        time.sleep(seconds)
