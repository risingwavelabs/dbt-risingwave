from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, Optional

from dbt.adapters.relation_configs import RelationConfigValidationMixin
from dbt.contracts.graph.nodes import ModelNode
from dbt_common.exceptions import CompilationError

from dbt.adapters.risingwave.relation_configs.base import (
    RisingWaveRelationConfigBase,
)


@dataclass(frozen=True, eq=True, unsafe_hash=True)
class RisingWaveSinkConfig(
    RisingWaveRelationConfigBase,
    RelationConfigValidationMixin,
):
    """
    Dataclass for the RisingWave sink relation configuration.
    """

    connector: str
    data_format: Optional[str] = None
    data_encode: Optional[str] = None
    sink_values: Dict = field(default_factory=dict)
    format_values: Dict = field(default_factory=dict)

    @classmethod
    def parse_relation_config(cls, relation_config: ModelNode) -> Dict:
        """
        Constructor method to parse the relation_config.

        Parameters
        ----------
        relation_config : ModelNode
            The relation_config to parse. Used via e.g. `config.model`.

        Returns
        -------
        Dict
            The parsed relation_config as a dictionary.
        """

        if not (connector := relation_config.config.get("connector")):
            raise CompilationError(f"got connector='{connector}', required.")
        if not (sink_values := relation_config.config.get("sink_values")):
            raise CompilationError(f"got sink_values='{sink_values}', required.")

        return {
            "connector": connector,
            "data_format": relation_config.config.get("data_format"),
            "data_encode": relation_config.config.get("data_encode"),
            "sink_values": sink_values,
            "format_values": relation_config.config.get("format_values"),
        }

    @property
    def with_statement(self) -> str:
        """
        Construct the `WITH` statement for the relation.

        Returns
        -------
        str
            The `WITH` statement for the relation.
        """
        builder = f"""
        connector = '{self.connector}',
        """

        for k, v in self.sink_values.items():
            if not v:
                continue
            builder += f"{k} = '{v}',\n"
        return builder[:-2]

    @property
    def has_format_values(self) -> bool:
        """
        Whether the user specified format encoding and format values.

        Returns
        -------
        bool
            Whether the user specified format encoding and format values.
        """
        return len(self.format_values) > 0 and bool(self.data_format) and bool(self.data_encode)

    @property
    def format_parameters(self) -> str:
        """
        Construct the format parameters for the relation.

        Returns
        -------
        str
            The format parameters for the relation.
        """
        if not self.has_format_values:
            return ""
        builder = ""
        for k, v in self.format_values.items():
            if not v:
                continue
            builder += f"{k} = '{v}',\n"
        return builder[:-2]
