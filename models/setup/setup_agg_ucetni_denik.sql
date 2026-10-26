{{ config(alias='SETUP_AGG_UCETNI_DENIK') }}

/*
 * Port of "AGG_UCETNI_DENIK - create table": creates an EMPTY AGG_UCETNI_DENIK with the original column definitions.
 * The Keboola output mapping writes it to AGG_UCETNI_DENIK (full load), i.e. it resets the table.
 */

SELECT
    CAST(NULL AS VARCHAR(3)) AS "SOURCE",
    CAST(NULL AS VARCHAR) AS "UCET",
    CAST(NULL AS VARCHAR) AS "COUNTER_ACCOUNT",
    CAST(NULL AS DATE) AS "PERIOD",
    CAST(NULL AS NUMBER(18,2)) AS "SUM_TUZ",
    CAST(NULL AS VARCHAR) AS "STREDISKO",
    CAST(NULL AS VARCHAR) AS "ZAKAZKA",
    CAST(NULL AS VARCHAR) AS "CINNOST"
WHERE FALSE
