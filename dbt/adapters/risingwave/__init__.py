from dbt.adapters.risingwave.connections import RisingWaveConnectionManager # noqa
from dbt.adapters.risingwave.connections import RisingWaveCredentials
from dbt.adapters.risingwave.impl import RisingWaveAdapter

from dbt.adapters.base import AdapterPlugin
from dbt.include import risingwave


Plugin = AdapterPlugin(
    adapter=RisingWaveAdapter,
    credentials=RisingWaveCredentials,
    include_path=risingwave.PACKAGE_PATH,
    dependencies=["postgres"],
)
