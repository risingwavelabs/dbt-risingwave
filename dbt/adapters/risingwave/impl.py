
from typing import Optional, List
from dbt.adapters.sql import SQLAdapter as adapter_cls
from dbt.adapters.base.relation import BaseRelation 
from dbt.adapters.risingwave import RisingWaveConnectionManager
from dbt.adapters.postgres import PostgresAdapter


class RisingWaveAdapter(PostgresAdapter):
    ConnectionManager = RisingWaveConnectionManager
    def rename_relation(self, from_relation , to_relation ) -> None:
        pass
    def _link_cached_relations(self, manifest):
        # lack of `pg_depend`, `pg_rewrite`
        pass
