{{ config(alias='AGG_UCETNI_DENIK') }}

/*
 * dbt port of "002-Aggregate ucetni denik".
 * Monthly totals of SUM_TUZ by side, account, counter-account and dimensions.
 * Reads source STG_UCETNI_DENIK (input mapping), so this tag does not rebuild
 * normalize_ud or initiate_stg.
 */

SELECT
    "SOURCE",
    "UCET",
    "COUNTER_ACCOUNT",
    DATE_TRUNC('MONTH', "DAT_UCTO")  AS "PERIOD",
    SUM("SUM_TUZ")                   AS "SUM_TUZ",
    COALESCE("STREDISKO", '')        AS "STREDISKO",
    COALESCE("ZAKAZKA", '')          AS "ZAKAZKA",
    COALESCE("CINNOST", '')          AS "CINNOST"
FROM {{ source('l2_input', 'STG_UCETNI_DENIK') }}
GROUP BY
    "SOURCE",
    "UCET",
    "COUNTER_ACCOUNT",
    DATE_TRUNC('MONTH', "DAT_UCTO"),
    "STREDISKO",
    "ZAKAZKA",
    "CINNOST"
