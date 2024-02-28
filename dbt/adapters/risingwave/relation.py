from dataclasses import dataclass
from typing import Optional, Type

from dbt.adapters.postgres.relation import PostgresRelation
from dbt.adapters.relation_configs.config_base import RelationConfigBase
from dbt.contracts.graph.nodes import ModelNode
from dbt.exceptions import DbtRuntimeError
from dbt.utils import classproperty

from dbt.adapters.risingwave.relation_configs.base import RisingWaveRelationType
from dbt.adapters.risingwave.relation_configs.sink import RisingWaveSinkConfig


@dataclass(frozen=True, eq=False, repr=False)
class RisingWaveRelation(PostgresRelation):
    type: Optional[RisingWaveRelationType] = None  # type: ignore
    relation_configs = {
        RisingWaveRelationType.Sink.value: RisingWaveSinkConfig,
    }

    @classproperty
    def get_relation_type(cls) -> Type[RisingWaveRelationType]:
        return RisingWaveRelationType

    # RisingWave has no limitation on relation name length.
    # We set a relatively large value right now.
    def relation_max_name_length(self):
        return 1024

    @classmethod
    def from_config(cls, config: ModelNode) -> RelationConfigBase:
        relation_type: str = config.config.materialized  # type: ignore

        if rel_configs := cls.relation_configs.get(relation_type):
            return rel_configs.from_relation_config(config)
        raise DbtRuntimeError("from_config() is not supported for relation type:", relation_type)
