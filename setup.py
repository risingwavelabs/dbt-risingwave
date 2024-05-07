#!/usr/bin/env python
import os
from setuptools import find_namespace_packages, setup

package_name = "dbt-risingwave"
# make sure this always matches dbt/adapters/{adapter}/__version__.py
package_version = "1.7.4"
description = """The RisingWave adapter plugin for dbt"""

with open(os.path.join(os.path.dirname(__file__), "README.md")) as f:
    README = f.read()

setup(
    name=package_name,
    version=package_version,
    description=description,
    long_description=README,
    long_description_content_type="text/markdown",
    license="http://www.apache.org/licenses/LICENSE-2.0",
    keywords="dbt RisingWave",
    author="Dylan Chen",
    author_email="zilin@risingwave-labs.com",
    url="https://github.com/risingwavelabs/dbt-risingwave",
    packages=find_namespace_packages(include=["dbt", "dbt.*"]),
    include_package_data=True,
    install_requires=["dbt-postgres~=1.7.0"],
)
