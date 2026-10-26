{#- Ported 1:1 from Snowflake transformation "005-Populate RPT_UCETNI_DENIK (BS)". Runs as a post-hook on the step's model; tgt = that model. -#}
{% macro rpt_005_1_merge_bs_calc_cye(tgt) %}
MERGE INTO {{ tgt }} AS "TGT"
USING ( 
WITH  "MONTHLY" AS (
        SELECT
            "METRIC_CODE",
            "PERIOD",
            CAST(
                CEIL(MONTH("PERIOD") / 3) AS NUMBER(1, 0)
            ) AS "QUARTER",
            YEAR("PERIOD") AS "YEAR",
            CAST(
              SUM("SUM_PM") * -1 AS NUMBER(18, 6)
            )AS "SUM_PM"            
        FROM {{ tgt }}
        WHERE "METRIC_CODE" IN ('pnl_calc_ebt')
        GROUP BY "METRIC_CODE", "PERIOD", "QUARTER", "YEAR"

    ),

    -- "BS_MONTHLY" AS (
    --     SELECT
    --         "METRIC_CODE",
    --         "PERIOD",
    --         "QUARTER",
    --         "YEAR",
    --         CAST(SUM("SUM_PM") AS NUMBER(18, 6)) AS "SUM_PM"
    --     FROM "MONTHLY"
    --     //WHERE "METRIC_CODE" ILIKE 'bs_%'
    --     GROUP BY "METRIC_CODE", "PERIOD", "QUARTER", "YEAR"
    -- ),
    "BS_CALC" AS (
        SELECT
            'bs_calc_cye' AS "METRIC_CODE",
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
        FROM "MONTHLY"
    
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

    FROM "BS_CALC"

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
    "SUM_YTD" = "SRC"."SUM_YTD"
WHEN NOT MATCHED THEN INSERT (
    "METRIC_CODE", "PERIOD", "QUARTER", "YEAR", "STREDISKO", "ZAKAZKA", "CINNOST",
    "SUM_PM", "SUM_PQ", "SUM_YTD"
) VALUES (
    "SRC"."METRIC_CODE", "SRC"."PERIOD", "SRC"."QUARTER", "SRC"."YEAR",
    "SRC"."STREDISKO", "SRC"."ZAKAZKA", "SRC"."CINNOST",
    "SRC"."SUM_PM", "SRC"."SUM_PQ", "SRC"."SUM_YTD"
  )
{% endmacro %}
