from pathlib import Path

import pytest

from dbt.tests.util import get_relation_columns, relation_from_name, run_dbt, write_file


_MODEL_INITIAL = """
{{ config(materialized='table_with_connector') }}

CREATE TABLE {{ this }} (
    id int,
    payload varchar
) WITH (
    appendonly = 'true'
);
"""

_MODEL_ADD_COLUMNS = """
{{ config(
    materialized='table_with_connector',
    on_schema_change='append_new_columns',
    additive_schema_evolution=[
      {'name': 'source_ts', 'data_type': 'timestamp'},
      {'name': 'score', 'data_type': 'double precision', 'default': '0.0'}
    ]
) }}

CREATE TABLE {{ this }} (
    id int,
    payload varchar,
    source_ts timestamp,
    score double precision
) WITH (
    appendonly = 'true'
);
"""


class TestTableWithConnectorSchemaEvolution:
    @pytest.fixture(scope="class")
    def models(self):
        return {"schema_evolution_table.sql": _MODEL_INITIAL}

    def test_append_new_columns_with_current_adapter(self, project):
        results = run_dbt(["run", "--select", "schema_evolution_table"])
        assert len(results) == 1

        relation = relation_from_name(project.adapter, "schema_evolution_table")
        project.run_sql(f"insert into {relation} values (1, 'before')")

        model_path = Path(project.project_root) / "models" / "schema_evolution_table.sql"
        write_file(_MODEL_ADD_COLUMNS, model_path)

        results = run_dbt(["run", "--select", "schema_evolution_table"])
        assert len(results) == 1

        columns = [name for name, _, _ in get_relation_columns(project.adapter, "schema_evolution_table")]
        assert columns == ["id", "payload", "score", "source_ts"]

        project.run_sql(
            f"""
            insert into {relation} (id, payload, source_ts, score)
            values (2, 'after', timestamp '2026-04-27 00:00:00', 9.5)
            """
        )
        rows = project.run_sql(
            f"""
            select id, payload, source_ts is null as source_ts_is_null, score
            from {relation}
            order by id
            """,
            fetch="all",
        )

        assert rows == [
            (1, "before", True, None),
            (2, "after", False, 9.5),
        ]
