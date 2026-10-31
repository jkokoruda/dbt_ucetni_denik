{#- Ported 1:1 from Snowflake transformation "003-Populate RPT_UCETNI_DENIK". Runs as a post-hook on the step's model; tgt = that model. -#}
{% macro rpt_003_1_merge_base_metrics(tgt) %}
-- Ensure table exists with proper structure
-- CREATE TABLE IF NOT EXISTS {{ tgt }} (
--     "METRIC_CODE" VARCHAR,
--     "PERIOD" DATE,
--     "QUARTER" NUMBER(1,0),
--     "YEAR" NUMBER,
--     "STREDISKO" VARCHAR,
--     "ZAKAZKA" VARCHAR,
--     "CINNOST" VARCHAR,
--     "SUM_PM" NUMBER(18,6),
--     "SUM_PQ" NUMBER(18,6),
--     "SUM_YTD" NUMBER(18,6),
--     "SUM_LM" NUMBER(18,6),
--     "SUM_LQ" NUMBER(18,6),
--     "SUM_LYTD" NUMBER(18,6),
--     "SUM_LYM" NUMBER(18,6),
--     "DIFF_LM" NUMBER(18,6),
--     "DIFF_LQ" NUMBER(18,6),
--     "DIFF_LYTD" NUMBER(18,6),
--     "DIFF_LYM" NUMBER(18,6),
--     "PCH_LM" NUMBER(18,6),
--     "PCH_LQ" NUMBER(18,6),
--     "PCH_LYTD" NUMBER(18,6),
--     "PCH_LYM" NUMBER(18,6)
-- );

-- Upsert data from AGG_UCETNI_DENIK joined to MAP_UCET_ITEM
MERGE INTO {{ tgt }} AS "TGT"
USING (
    WITH "MONTHLY_RAW" AS (
    -- Raw aggregation from source; no period gaps filled yet
    SELECT
        "MUI"."ITEM_CODE"                                       AS "METRIC_CODE",
        "AGUD"."PERIOD"                                         AS "PERIOD",
        CAST(CEIL(MONTH("AGUD"."PERIOD") / 3) AS NUMBER(1, 0)) AS "QUARTER",
        YEAR("AGUD"."PERIOD")                                   AS "YEAR",
        COALESCE("AGUD"."STREDISKO", '')                           AS "STREDISKO",
        COALESCE("AGUD"."ZAKAZKA", '')                             AS "ZAKAZKA",
        COALESCE("AGUD"."CINNOST", '')                             AS "CINNOST",
        CAST(
            SUM(
                CASE
                    WHEN "MUI"."ITEM_CODE" ILIKE 'bs_%'
                        THEN "AGUD"."SUM_TUZ" * -1
                    ELSE "AGUD"."SUM_TUZ"
                END
            ) AS NUMBER(18, 6)
        )                                                       AS "SUM_PM"
    FROM {{ source('l2_input', 'AGG_UCETNI_DENIK') }} AS "AGUD"
    INNER JOIN {{ source('l2_input', 'MAP_UCET_ITEM') }} AS "MUI"
        ON "AGUD"."UCET" = "MUI"."UCET"
    WHERE "MUI"."ITEM_CODE" IS NOT NULL
    GROUP BY
        "MUI"."ITEM_CODE",
        "AGUD"."PERIOD",
        CAST(CEIL(MONTH("AGUD"."PERIOD") / 3) AS NUMBER(1, 0)),
        YEAR("AGUD"."PERIOD"),
        "AGUD"."STREDISKO",
        "AGUD"."ZAKAZKA",
        "AGUD"."CINNOST"
),

-- All distinct periods that exist anywhere in the data
"PERIODS" AS (
    SELECT DISTINCT
        "PERIOD",
        CAST(CEIL(MONTH("PERIOD") / 3) AS NUMBER(1, 0)) AS "QUARTER",
        YEAR("PERIOD")                                   AS "YEAR"
    FROM "MONTHLY_RAW"
),

-- First and last active period for every dimension combination (pnl_ metrics only)
-- LAST_YEAR is used to extend the spine to EOY even if the combo stopped mid-year
"COMBO_RANGE" AS (
    SELECT
        "METRIC_CODE",
        "STREDISKO",
        "ZAKAZKA",
        "CINNOST",
        DATE_TRUNC('QUARTER', MIN("PERIOD"))      AS "FIRST_PERIOD",
        MAX("PERIOD")        AS "LAST_PERIOD",
        YEAR(MAX("PERIOD"))  AS "LAST_YEAR"   -- EOY anchor
    FROM "MONTHLY_RAW"
    WHERE "METRIC_CODE" ILIKE 'pnl_%'
    GROUP BY
        "METRIC_CODE",
        "STREDISKO",
        "ZAKAZKA",
        "CINNOST"
),

-- Spine: every combination × every period within its active range
-- Lower bound : FIRST_PERIOD  (combo not padded before it first appeared)
-- Upper bound : last period of LAST_YEAR  (combo padded with 0 through EOY)
"SPINE" AS (
    SELECT
        CR."METRIC_CODE",
        P."PERIOD",
        P."QUARTER",
        P."YEAR",
        CR."STREDISKO",
        CR."ZAKAZKA",
        CR."CINNOST"
    FROM "COMBO_RANGE" AS CR
    INNER JOIN "PERIODS" AS P
        ON  P."PERIOD" >= CR."FIRST_PERIOD"   -- start at first active month
        AND P."YEAR"   <= CR."LAST_YEAR"       -- extend to end of last active year
),

-- First period each bs_ metric ever appeared (metric-level only)
"BS_COMBO_RANGE" AS (
    SELECT
        "METRIC_CODE",
        DATE_TRUNC('QUARTER', MIN("PERIOD")) AS "FIRST_PERIOD"
    FROM "MONTHLY_RAW"
    WHERE "METRIC_CODE" ILIKE 'bs_%'
    GROUP BY "METRIC_CODE"
),

-- Global ceiling: the very last period present anywhere in the data
"BS_LAST_PERIOD" AS (
    SELECT MAX("PERIOD") AS "LAST_PERIOD"
    FROM "MONTHLY_RAW"
),

-- Spine: every bs_ metric × every period from its first appearance
--        through the global last period (no year boundary)
"BS_SPINE" AS (
    SELECT
        CR."METRIC_CODE",
        P."PERIOD",
        P."QUARTER",
        P."YEAR"
    FROM "BS_COMBO_RANGE"  AS CR
    CROSS JOIN "BS_LAST_PERIOD" AS LP
    INNER JOIN "PERIODS"   AS P
        ON  P."PERIOD" >= CR."FIRST_PERIOD"   -- start at first active month
        AND P."PERIOD" <= LP."LAST_PERIOD"    -- run to global last period (no reset)
),
  
-- Full monthly series: missing periods filled with 0 so window functions are correct
"PNL_MONTHLY" AS (
    SELECT
        S."METRIC_CODE",
        S."PERIOD",
        S."QUARTER",
        S."YEAR",
        S."STREDISKO",
        S."ZAKAZKA",
        S."CINNOST",
        CAST(COALESCE(M."SUM_PM", 0) AS NUMBER(18, 6)) AS "SUM_PM"
    FROM "SPINE" AS S
    LEFT JOIN "MONTHLY_RAW" AS M
        ON  M."METRIC_CODE" = S."METRIC_CODE"
        AND M."PERIOD"      = S."PERIOD"
        AND M."STREDISKO"   = S."STREDISKO"
        AND M."ZAKAZKA"     = S."ZAKAZKA"
        AND M."CINNOST"     = S."CINNOST"
),
    "PNL_CALC" AS (
        SELECT
            "METRIC_CODE",
            "PERIOD",
            "QUARTER",
            "YEAR",
            "STREDISKO",
            "ZAKAZKA",
            "CINNOST",
            "SUM_PM",
            CAST(
                SUM("SUM_PM") OVER (
                    PARTITION BY "METRIC_CODE", "YEAR", "QUARTER", "STREDISKO", "ZAKAZKA", "CINNOST"
                ) AS NUMBER(18, 6)
            ) AS "SUM_PQ",
            CAST(
                SUM("SUM_PM") OVER (
                    PARTITION BY "METRIC_CODE", "YEAR", "STREDISKO", "ZAKAZKA", "CINNOST"
                    ORDER BY "PERIOD"
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ) AS NUMBER(18, 6)
            ) AS "SUM_YTD"
        FROM "PNL_MONTHLY"
        WHERE "METRIC_CODE" ILIKE 'pnl_%'
    ),
    "BS_MONTHLY_RAW_AGG" AS (
        SELECT
            "METRIC_CODE",
            "PERIOD",
            "QUARTER",
            "YEAR",
            CAST(SUM("SUM_PM") AS NUMBER(18, 6)) AS "SUM_PM"
        FROM "MONTHLY_RAW"
        WHERE "METRIC_CODE" ILIKE 'bs_%'
        GROUP BY "METRIC_CODE", "PERIOD", "QUARTER", "YEAR"
    ),

"BS_MONTHLY" AS (
    SELECT
        S."METRIC_CODE",
        S."PERIOD",
        S."QUARTER",
        S."YEAR",
        CAST(COALESCE(M."SUM_PM", 0) AS NUMBER(18, 6)) AS "SUM_PM"
    FROM "BS_SPINE" AS S
    LEFT JOIN "BS_MONTHLY_RAW_AGG" AS M
        ON  M."METRIC_CODE" = S."METRIC_CODE"
        AND M."PERIOD"      = S."PERIOD"
),
  
    "BS_CALC" AS (
        SELECT
            "METRIC_CODE",
            "PERIOD",
            "QUARTER",
            "YEAR",
            '' AS "STREDISKO",
            '' AS "ZAKAZKA",
            '' AS "CINNOST",
            "SUM_PM",
            CAST(
                SUM("SUM_PM") OVER (
                    PARTITION BY "METRIC_CODE", "YEAR", "QUARTER"
                ) AS NUMBER(18, 6)
            ) AS "SUM_PQ",
            CAST(
                SUM("SUM_PM") OVER (
                    PARTITION BY "METRIC_CODE"
                    ORDER BY "PERIOD"
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ) AS NUMBER(18, 6)
            ) AS "SUM_YTD"
        FROM "BS_MONTHLY"
    ),
    "COMBINED" AS (
        SELECT
            "METRIC_CODE",
            "PERIOD",
            "QUARTER",
            "YEAR",
            "STREDISKO",
            "ZAKAZKA",
            "CINNOST",
            "SUM_PM",
            "SUM_PQ",
            "SUM_YTD"
        FROM "PNL_CALC"
        UNION ALL
        SELECT
            "METRIC_CODE",
            "PERIOD",
            "QUARTER",
            "YEAR",
            "STREDISKO",
            "ZAKAZKA",
            "CINNOST",
            "SUM_PM",
            "SUM_PQ",
            "SUM_YTD"
        FROM "BS_CALC"
    )
    SELECT
        "METRIC_CODE",
        "PERIOD",
        "QUARTER",
        "YEAR",
        "STREDISKO",
        "ZAKAZKA",
        "CINNOST",
        CAST("SUM_PM" AS NUMBER(18, 6)) AS "SUM_PM",
        CAST("SUM_PQ" AS NUMBER(18, 6)) AS "SUM_PQ",
        CAST("SUM_YTD" AS NUMBER(18, 6)) AS "SUM_YTD",
        CAST(NULL AS NUMBER(18, 6)) AS "SUM_LM",
        CAST(NULL AS NUMBER(18, 6)) AS "SUM_LQ",
        CAST(NULL AS NUMBER(18, 6)) AS "SUM_LYTD",
        CAST(NULL AS NUMBER(18, 6)) AS "SUM_LYM",
        CAST(NULL AS NUMBER(18, 6)) AS "DIFF_LM",
        CAST(NULL AS NUMBER(18, 6)) AS "DIFF_LQ",
        CAST(NULL AS NUMBER(18, 6)) AS "DIFF_LYTD",
        CAST(NULL AS NUMBER(18, 6)) AS "DIFF_LYM",
        CAST(NULL AS NUMBER(18, 6)) AS "PCH_LM",
        CAST(NULL AS NUMBER(18, 6)) AS "PCH_LQ",
        CAST(NULL AS NUMBER(18, 6)) AS "PCH_LYTD",
        CAST(NULL AS NUMBER(18, 6)) AS "PCH_LYM"
    FROM "COMBINED"
) AS "SRC"
ON "TGT"."METRIC_CODE" = "SRC"."METRIC_CODE"
    AND "TGT"."PERIOD" = "SRC"."PERIOD"
    AND COALESCE("TGT"."STREDISKO", '') = COALESCE("SRC"."STREDISKO", '')
    AND COALESCE("TGT"."ZAKAZKA", '') = COALESCE("SRC"."ZAKAZKA", '')
    AND COALESCE("TGT"."CINNOST", '') = COALESCE("SRC"."CINNOST", '')
WHEN MATCHED THEN UPDATE SET
    "QUARTER" = "SRC"."QUARTER",
    "YEAR" = "SRC"."YEAR",
    "SUM_PM" = "SRC"."SUM_PM",
    "SUM_PQ" = "SRC"."SUM_PQ",
    "SUM_YTD" = "SRC"."SUM_YTD",
    "SUM_LM" = "SRC"."SUM_LM",
    "SUM_LQ" = "SRC"."SUM_LQ",
    "SUM_LYTD" = "SRC"."SUM_LYTD",
    "SUM_LYM" = "SRC"."SUM_LYM",
    "DIFF_LM" = "SRC"."DIFF_LM",
    "DIFF_LQ" = "SRC"."DIFF_LQ",
    "DIFF_LYTD" = "SRC"."DIFF_LYTD",
    "DIFF_LYM" = "SRC"."DIFF_LYM",
    "PCH_LM" = "SRC"."PCH_LM",
    "PCH_LQ" = "SRC"."PCH_LQ",
    "PCH_LYTD" = "SRC"."PCH_LYTD",
    "PCH_LYM" = "SRC"."PCH_LYM"
WHEN NOT MATCHED THEN INSERT (
    "METRIC_CODE", "PERIOD", "QUARTER", "YEAR", "STREDISKO", "ZAKAZKA", "CINNOST",
    "SUM_PM", "SUM_PQ", "SUM_YTD", "SUM_LM", "SUM_LQ", "SUM_LYTD", "SUM_LYM",
    "DIFF_LM", "DIFF_LQ", "DIFF_LYTD", "DIFF_LYM", "PCH_LM", "PCH_LQ", "PCH_LYTD", "PCH_LYM"
) VALUES (
    "SRC"."METRIC_CODE", "SRC"."PERIOD", "SRC"."QUARTER", "SRC"."YEAR",
    "SRC"."STREDISKO", "SRC"."ZAKAZKA", "SRC"."CINNOST",
    "SRC"."SUM_PM", "SRC"."SUM_PQ", "SRC"."SUM_YTD", "SRC"."SUM_LM",
    "SRC"."SUM_LQ", "SRC"."SUM_LYTD", "SRC"."SUM_LYM",
    "SRC"."DIFF_LM", "SRC"."DIFF_LQ", "SRC"."DIFF_LYTD", "SRC"."DIFF_LYM",
    "SRC"."PCH_LM", "SRC"."PCH_LQ", "SRC"."PCH_LYTD", "SRC"."PCH_LYM"
)
{% endmacro %}
