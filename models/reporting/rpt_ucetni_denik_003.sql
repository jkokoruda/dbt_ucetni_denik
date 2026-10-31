{{ config(
    post_hook=[
        "{{ rpt_003_1_merge_base_metrics(this) }}",
        "{{ rpt_003_2_merge_parent_rollup(this) }}",
        "{{ rpt_003_3_merge_calc_metrics(this) }}",
        "{{ rpt_003_4_update_calc_pq_ytd(this) }}"
    ]
) }}

/*
 * dbt port of "003-Populate RPT_UCETNI_DENIK".
 * The table is copied from the previous step, then the original SQL statements
 * run on it in the original order (see macros/rpt/).
 */

-- Start from the current report table (same state the original 003 reads).
-- AGG_UCETNI_DENIK is a source loaded by input mapping, not a ref, so this tag
-- does not rebuild the aggregate step.
SELECT
    CAST("METRIC_CODE" AS VARCHAR) AS "METRIC_CODE",
    CAST("PERIOD" AS DATE) AS "PERIOD",
    CAST("QUARTER" AS NUMBER(1,0)) AS "QUARTER",
    CAST("YEAR" AS NUMBER(38,0)) AS "YEAR",
    CAST("STREDISKO" AS VARCHAR) AS "STREDISKO",
    CAST("ZAKAZKA" AS VARCHAR) AS "ZAKAZKA",
    CAST("CINNOST" AS VARCHAR) AS "CINNOST",
    CAST("SUM_PM" AS NUMBER(18,6)) AS "SUM_PM",
    CAST("SUM_PQ" AS NUMBER(18,6)) AS "SUM_PQ",
    CAST("SUM_YTD" AS NUMBER(18,6)) AS "SUM_YTD",
    CAST("SUM_LM" AS NUMBER(18,6)) AS "SUM_LM",
    CAST("SUM_LQ" AS NUMBER(18,6)) AS "SUM_LQ",
    CAST("SUM_LYTD" AS NUMBER(18,6)) AS "SUM_LYTD",
    CAST("SUM_LYM" AS NUMBER(18,6)) AS "SUM_LYM",
    CAST("DIFF_LM" AS NUMBER(18,6)) AS "DIFF_LM",
    CAST("DIFF_LQ" AS NUMBER(18,6)) AS "DIFF_LQ",
    CAST("DIFF_LYTD" AS NUMBER(18,6)) AS "DIFF_LYTD",
    CAST("DIFF_LYM" AS NUMBER(18,6)) AS "DIFF_LYM",
    CAST("PCH_LM" AS NUMBER(18,6)) AS "PCH_LM",
    CAST("PCH_LQ" AS NUMBER(18,6)) AS "PCH_LQ",
    CAST("PCH_LYTD" AS NUMBER(18,6)) AS "PCH_LYTD",
    CAST("PCH_LYM" AS NUMBER(18,6)) AS "PCH_LYM",
    CAST("SUM_AVG3M" AS NUMBER(18,6)) AS "SUM_AVG3M",
    CAST("SUM_AVG6M" AS NUMBER(18,6)) AS "SUM_AVG6M",
    CAST("SUM_AVG12M" AS NUMBER(18,6)) AS "SUM_AVG12M"
FROM {{ source('l2_input', 'RPT_UCETNI_DENIK_PREV') }}
