-- todo: filter out temporary schema when `pg_is_other_temp_schema` is done in rw
-- todo: filter out temporary table when `tbl.relpersistence` is done in rw
-- todo: add sink support when it's shown in `pg_catalog.pg_class`
{% macro risingwave__get_catalog(information_schema, schemas) -%}

  {% set database = information_schema.database %}
  {{ adapter.verify_database(database) }}

  {%- call statement('catalog', fetch_result=True) -%}
  SELECT
   '{{ database }}' AS table_database,
	sch.nspname AS table_schema,
	tbl.relname AS table_name,
	CASE tbl.relkind
	WHEN 'v' THEN
		'VIEW'
	WHEN 'x' THEN
		'SOURCE'
	ELSE
		'BASE TABLE'
	END AS table_type,
	tbl_desc.description AS table_comment,
	col.attname AS column_name,
	col.attnum AS column_index,
	pg_catalog.format_type(col.atttypid, NULL) AS column_type,
	col_desc.description AS column_comment,
	pg_get_userbyid(tbl.relowner) AS table_owner
FROM
	pg_catalog.pg_namespace sch
	JOIN pg_catalog.pg_class tbl ON tbl.relnamespace = sch.oid
	JOIN pg_catalog.pg_attribute col ON col.attrelid = tbl.oid
	LEFT OUTER JOIN pg_catalog.pg_description tbl_desc ON (tbl_desc.objoid = tbl.oid
			AND tbl_desc.objsubid = 0)
	LEFT OUTER JOIN pg_catalog.pg_description col_desc ON (col_desc.objoid = tbl.oid
		AND col_desc.objsubid = col.attnum)
WHERE (
        {%- for schema in schemas -%}
          upper(sch.nspname) = upper('{{ schema }}'){%- if not loop.last %} or {% endif -%}
        {%- endfor -%}
      )
	AND tbl.relkind in('r', 'v', 'f', 'p', 'x') -- o[r]dinary table, [v]iew, [f]oreign table, [p]artitioned table, [x] source. Other values are [i]ndex, [S]equence, [c]omposite type, [t]OAST table, [m]aterialized view
	AND col.attnum > 0 -- negative numbers are used for system columns such as oid
	AND NOT col.attisdropped -- column as not been dropped
ORDER BY
	sch.nspname,
	tbl.relname,
	col.attnum
  {%- endcall -%}
  {{ return(load_result('catalog').table) }}
{%- endmacro %}