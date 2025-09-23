from dataclasses import dataclass
from typing import Optional, Type

from dbt.adapters.postgres.relation import PostgresRelation
from dbt.adapters.utils import classproperty
from dbt.adapters.relation_configs.config_base import RelationResults
from dbt.adapters.contracts.relation import RelationConfig
from dbt_common.dataclass_schema import StrEnum

from dbt.adapters.risingwave.relation_configs.materialized_view import (
    RisingWaveMaterializedViewConfig,
    RisingWaveMaterializedViewConfigChangeCollection,
)
from dbt.adapters.risingwave.relation_configs.index import (
    RisingWaveIndexConfig,
    RisingWaveIndexConfigChange,
)


class RisingWaveRelationType(StrEnum):
    Table = "table"
    View = "view"
    CTE = "cte"
    MaterializedView = "materialized_view"
    MaterializedView_v1_5_0 = "materializedview"
    External = "external"

    Source = "source"
    Sink = "sink"


@dataclass(frozen=True, eq=False, repr=False)
class RisingWaveRelation(PostgresRelation):
    type: Optional[RisingWaveRelationType] = None

    @classproperty
    def get_relation_type(cls) -> Type[RisingWaveRelationType]:
        return RisingWaveRelationType

    # RisingWave has no limitation on relation name length.
    # We set a relatively large value right now.
    def relation_max_name_length(self):
        return 1024

    def get_materialized_view_config_change_collection(
        self, relation_results: RelationResults, relation_config: RelationConfig
    ) -> Optional[RisingWaveMaterializedViewConfigChangeCollection]:
        config_change_collection = RisingWaveMaterializedViewConfigChangeCollection()

        existing_materialized_view = (
            RisingWaveMaterializedViewConfig.from_relation_results(relation_results)
        )
        new_materialized_view = RisingWaveMaterializedViewConfig.from_config(
            relation_config
        )

        config_change_collection.indexes = self._get_index_config_changes(
            set(existing_materialized_view.indexes), set(new_materialized_view.indexes)
        )

        # we return `None` instead of an empty `PostgresMaterializedViewConfigChangeCollection` object
        # so that it's easier and more extensible to check in the materialization:
        # `core/../materializations/materialized_view.sql` :
        #     {% if configuration_changes is none %}
        if config_change_collection.has_changes:
            return config_change_collection
        return None
