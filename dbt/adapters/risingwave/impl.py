from dbt.adapters.postgres.impl import PostgresAdapter

from dbt.adapters.risingwave.connections import RisingWaveConnectionManager
from dbt.adapters.risingwave.relation import RisingWaveRelation


class RisingWaveAdapter(PostgresAdapter):
    ConnectionManager = RisingWaveConnectionManager
    Relation = RisingWaveRelation  # type: ignore

    def rename_relation(self, from_relation, to_relation) -> None:
        raise NotImplementedError("RisingWave does not support renaming relations yet")

    def _link_cached_relations(self, manifest):
        # lack of `pg_depend`, `pg_rewrite`
        pass
