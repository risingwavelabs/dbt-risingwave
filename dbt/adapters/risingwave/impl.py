from dbt.adapters.risingwave import RisingWaveConnectionManager
from dbt.adapters.postgres import PostgresAdapter


class RisingWaveAdapter(PostgresAdapter):
    ConnectionManager = RisingWaveConnectionManager

    def rename_relation(self, _from_relation, _to_relation) -> None:
        pass

    def _link_cached_relations(self, manifest):
        # lack of `pg_depend`, `pg_rewrite`
        pass
