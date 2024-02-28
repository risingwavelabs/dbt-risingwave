from dbt.adapters.base import AdapterPlugin

from dbt.adapters.risingwave.connections import (  # noqa: F401
    RisingWaveConnectionManager,
    RisingWaveCredentials,
)
from dbt.adapters.risingwave.impl import RisingWaveAdapter
from dbt.include import risingwave

Plugin = AdapterPlugin(
    adapter=RisingWaveAdapter,  # type: ignore
    credentials=RisingWaveCredentials,
    include_path=risingwave.PACKAGE_PATH,
    dependencies=["postgres"],
)
