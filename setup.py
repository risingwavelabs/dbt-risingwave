#!/usr/bin/env python
from pathlib import Path

from setuptools import find_namespace_packages, setup

# to get the long description
README = Path(__file__).parent / "README.md"
# update the version number in dbt/adapters/risingwave/__version__.py
VERSION = Path(__file__).parent / "dbt/adapters/risingwave/__version__.py"


def _plugin_version() -> str:
    """
    Pull the package version from the main package version file
    """
    attributes = {}
    exec(VERSION.read_text(), attributes)
    return attributes["version"]


setup(
    name="dbt-risingwave",
    version=_plugin_version(),
    description="The RisingWave adapter plugin for dbt",
    long_description=README.read_text(),
    long_description_content_type="text/markdown",
    license="http://www.apache.org/licenses/LICENSE-2.0",
    keywords="dbt RisingWave",
    author="Dylan Chen",
    author_email="zilin@risingwave-labs.com",
    url="https://github.com/risingwavelabs/dbt-risingwave",
    packages=find_namespace_packages(include=["dbt", "dbt.*"]),
    include_package_data=True,
    install_requires=[
        "dbt-postgres~=1.11.0",
        "dbt-core~=1.12.0",
        "dbt-common>=1.37.5,<2.0",
        "dbt-adapters>=1.24.5,<2.0",
    ],
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: Microsoft :: Windows",
        "Operating System :: MacOS :: MacOS X",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Programming Language :: Python :: 3.13",
    ],
    python_requires=">=3.10",
)
