{{ config(
    alias='SETUP_PS_UCETNI_DENIK',
    post_hook=[
        'ALTER TABLE {{ this }} ALTER COLUMN "UCET" SET NOT NULL',
        'ALTER TABLE {{ this }} ALTER COLUMN "DAT_UCTO" SET NOT NULL',
        'ALTER TABLE {{ this }} ALTER COLUMN "SUM_TUZ" SET NOT NULL',
        'ALTER TABLE {{ this }} ADD CONSTRAINT "PK_PS_UCETNI_DENIK" PRIMARY KEY ("UCET", "DAT_UCTO")'
    ]
) }}

/*
 * Port of refactoring/create_map_ps.sql: empty PS_UCETNI_DENIK.
 * UCET, DAT_UCTO, and SUM_TUZ are NOT NULL, primary key (UCET, DAT_UCTO).
 * The Keboola output mapping writes SETUP_PS_UCETNI_DENIK to PS_UCETNI_DENIK.
 */

SELECT
    CAST(NULL AS VARCHAR) AS "UCET",
    CAST(NULL AS DATE) AS "DAT_UCTO",
    CAST(NULL AS NUMBER(18,2)) AS "SUM_TUZ"
WHERE FALSE
