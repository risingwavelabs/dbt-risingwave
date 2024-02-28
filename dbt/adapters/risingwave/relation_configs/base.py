from __future__ import annotations

from dataclasses import dataclass
from typing import Dict

from dbt.adapters.relation_configs.config_base import RelationConfigBase
from dbt.contracts.graph.nodes import ModelNode
from dbt.dataclass_schema import StrEnum
from dbt_common.exceptions import NotImplementedError


class RisingWaveRelationType(StrEnum):
    """
    Enumeration of the RisingWave relation types.
    """

    Table = "table"
    View = "view"
    CTE = "cte"
    MaterializedView = "materialized_view"
    MaterializedView_v1_5_0 = "materializedview"
    External = "external"

    Source = "source"
    Sink = "sink"


@dataclass(frozen=True, eq=False, repr=False)
class RisingWaveRelationConfigBase(RelationConfigBase):
    """
    Extension of the RelationConfigBase class to include the RisingWave relation types.
    """

    @classmethod
    def from_relation_config(cls, relation_config: ModelNode) -> RisingWaveRelationConfigBase:
        relation_config_dict = cls.parse_relation_config(relation_config)
        relation = cls.from_dict(relation_config_dict)
        return relation  # type: ignore

    @classmethod
    def parse_relation_config(cls, _: ModelNode) -> Dict:
        raise NotImplementedError(
            "`parse_relation_config()` needs to be implemented on this RisingWaveRelationConfigBase instance"
        )
