{{ config(
    alias='SETUP_MAP_UCET_ITEM',
    post_hook=[
        'ALTER TABLE {{ this }} ALTER COLUMN "UCET" SET NOT NULL',
        'ALTER TABLE {{ this }} ALTER COLUMN "ITEM_CODE" SET NOT NULL',
        'ALTER TABLE {{ this }} ADD CONSTRAINT "PK_MAP_UCET_ITEM" PRIMARY KEY ("UCET", "ITEM_CODE")'
    ]
) }}

/*
 * Port of refactoring/create_map_ps.sql: empty MAP_UCET_ITEM.
 * UCET and ITEM_CODE are NOT NULL, primary key (UCET, ITEM_CODE).
 * The Keboola output mapping writes SETUP_MAP_UCET_ITEM to MAP_UCET_ITEM.
 * Row data stays external: the map seed is disabled.
 */

SELECT
    CAST(NULL AS VARCHAR) AS "UCET",
    CAST(NULL AS VARCHAR) AS "ITEM_CODE"
WHERE FALSE
