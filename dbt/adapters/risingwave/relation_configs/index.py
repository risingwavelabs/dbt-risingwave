from dataclasses import dataclass, field
from typing import Set

import agate
from dbt.adapters.relation_configs import (
    RelationConfigBase,
    RelationConfigValidationMixin,
    RelationConfigValidationRule,
    RelationConfigChangeAction,
)
from dbt_common.exceptions import DbtRuntimeError

from dbt.adapters.postgres.relation_configs.index import PostgresIndexConfigChange


@dataclass(frozen=True, eq=True, unsafe_hash=True)
class RisingWaveIndexConfig(RelationConfigBase, RelationConfigValidationMixin):
    """
    This config is an adaptation of the PostgresIndexConfig for RisingWave.
    """

    name: str = field(default="", hash=False, compare=False)
    column_names: tuple[str, ...] = field(default_factory=tuple, hash=True)

    @property
    def validation_rules(self) -> Set[RelationConfigValidationRule]:
        return {
            RelationConfigValidationRule(
                validation_check=self.column_names is not None
                and len(self.column_names) > 0,
                validation_error=DbtRuntimeError(
                    "Indexes require at least one column, but none were provided"
                ),
            ),
            RelationConfigValidationRule(
                validation_check=len(self.column_names) == len(set(self.column_names)),
                validation_error=DbtRuntimeError(
                    "Indexes require unique column names, but some are duplicated."
                ),
            ),
        }

    @classmethod
    def from_dict(cls, config_dict) -> "RisingWaveIndexConfig":
        kwargs_dict = {
            "name": config_dict.get("name"),
            "column_names": tuple(
                column.lower() for column in config_dict.get("column_names", [])
            ),
        }
        index: "RisingWaveIndexConfig" = super().from_dict(kwargs_dict)  # type: ignore
        return index

    @classmethod
    def parse_model_node(cls, model_node_entry: dict) -> dict:
        config_dict = {
            "column_names": tuple(model_node_entry.get("columns", [])),
        }
        return config_dict

    @classmethod
    def parse_relation_results(cls, relation_results_entry: agate.Row) -> dict:
        config_dict = {
            "name": relation_results_entry.get("name"),
            "column_names": tuple(
                relation_results_entry.get("column_names", "").split(",")
            ),
        }
        return config_dict

    @property
    def as_node_config(self) -> dict:
        node_config = {
            "columns": list(self.column_names),
        }
        return node_config


@dataclass(frozen=True, eq=True, unsafe_hash=True)
class RisingWaveIndexConfigChange(PostgresIndexConfigChange):
    context: RisingWaveIndexConfig

    @property
    def validation_rules(self) -> Set[RelationConfigValidationRule]:
        return {
            RelationConfigValidationRule(
                validation_check=self.action
                in {RelationConfigChangeAction.create, RelationConfigChangeAction.drop},
                validation_error=DbtRuntimeError(
                    "Invalid operation, only `drop` and `create` changes are supported for indexes."
                ),
            ),
            RelationConfigValidationRule(
                validation_check=not (
                    self.action == RelationConfigChangeAction.drop
                    and self.context.name is None
                ),
                validation_error=DbtRuntimeError(
                    "Invalid operation, attempting to drop an index with no name."
                ),
            ),
            RelationConfigValidationRule(
                validation_check=not (
                    self.action == RelationConfigChangeAction.create
                    and self.context.column_names == list()
                ),
                validation_error=DbtRuntimeError(
                    "Invalid operations, attempting to create an index with no columns."
                ),
            ),
        }
