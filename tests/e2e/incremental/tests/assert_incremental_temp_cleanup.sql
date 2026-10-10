-- Incremental runs build their temp relation as a regular table, because RisingWave
-- has no temporary tables. None may be left once a run of the model has succeeded.
select rw_schemas.name || '.' || rw_relations.name as leftover_temp_relation
from rw_catalog.rw_relations
join rw_catalog.rw_schemas on rw_relations.schema_id = rw_schemas.id
where rw_relations.name like '%\_\_dbt\_tmp%'
