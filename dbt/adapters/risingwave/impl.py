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

    def valid_incremental_strategies(self):
        """Builtin incremental strategies that RisingWave can execute.

        RisingWave has no MERGE statement, so `merge` and the inherited
        dbt-postgres microbatch implementation (which uses MERGE) are not
        available. `microbatch` uses the adapter's delete+insert implementation.
        """
        return ["append", "delete+insert", "microbatch"]

    @available
    @classmethod
    def sleep(cls, seconds):
        time.sleep(seconds)
