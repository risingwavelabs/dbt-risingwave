from dataclasses import dataclass
from typing import Optional, Type

from dbt.adapters.postgres import PostgresRelation
from dbt.dataclass_schema import StrEnum
from dbt.utils import classproperty


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
