{{ config(materialized='source') }}

create source {{ this }} (
    id integer,
    payload varchar
)
with (
    connector = 'datagen',
    fields.id.kind = 'sequence',
    fields.id.start = '1',
    fields.id.end = '100',
    fields.payload.kind = 'random',
    fields.payload.length = '8',
    fields.payload.seed = '7',
    datagen.rows.per.second = '5'
)
