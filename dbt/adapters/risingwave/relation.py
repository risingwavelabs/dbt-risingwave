from dataclasses import dataclass
from typing import Optional, Type

from dbt.adapters.postgres.relation import PostgresRelation
from dbt.adapters.utils import classproperty
from dbt_common.dataclass_schema import StrEnum


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
