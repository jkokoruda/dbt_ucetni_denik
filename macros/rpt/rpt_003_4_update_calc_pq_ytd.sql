{#- Ported 1:1 from Snowflake transformation "003-Populate RPT_UCETNI_DENIK". Runs as a post-hook on the step's model; tgt = that model. -#}
{% macro rpt_003_4_update_calc_pq_ytd(tgt) %}
MERGE INTO {{ tgt }} AS "TGT"
USING (
WITH
/*    "PIVOTED" AS (
        SELECT
            "PERIOD", "STREDISKO", "ZAKAZKA", "CINNOST",
            SUM(CASE WHEN "METRIC_CODE" = 'pnl_calc_opex' THEN "SUM_PM" END) AS "pnl_calc_opex",
            
            SUM(CASE WHEN "METRIC_CODE" = 'pnl_calc_rev' THEN "SUM_PM" END) AS "pnl_calc_rev",
            
            SUM(CASE WHEN "METRIC_CODE" = 'pnl_calc_cor' THEN "SUM_PM" END) AS "pnl_calc_cor",

    		SUM(CASE WHEN "METRIC_CODE" = 'pnl_exp_depr' THEN "SUM_PM" END) AS "pnl_exp_depr",

    		SUM(CASE WHEN "METRIC_CODE" = 'pnl_calc_fp' THEN "SUM_PM" END) AS "pnl_calc_fp",
            
    	FROM {{ tgt }}
        GROUP BY "PERIOD","STREDISKO", "ZAKAZKA", "CINNOST"
    ),

    "STEP_0" AS (SELECT *, CAST(COALESCE("pnl_calc_rev", 0) + COALESCE("pnl_calc_cor", 0) AS NUMBER(38,6)) AS "pnl_calc_gp" FROM "PIVOTED"),
    "STEP_1" AS (SELECT *, CAST(COALESCE("pnl_calc_gp", 0) / NULLIF("pnl_calc_rev", 0) AS NUMBER(38,6)) AS "pnl_calc_gm" FROM "STEP_0"),
    "STEP_2" AS (SELECT *, CAST(COALESCE("pnl_calc_gp", 0) + COALESCE("pnl_calc_opex", 0) AS NUMBER(38,6)) AS "pnl_calc_ebitda" FROM "STEP_1"),

    "STEP_3" AS (SELECT *, CAST(COALESCE("pnl_calc_ebitda", 0) + COALESCE("pnl_exp_depr", 0) AS NUMBER(38,6)) AS "pnl_calc_ebit" FROM "STEP_2"),
    "STEP_4" AS (SELECT *, CAST(COALESCE("pnl_calc_ebit", 0) / NULLIF("pnl_calc_rev", 0) AS NUMBER(38,6)) AS "pnl_calc_ebitm" FROM "STEP_3"),
    "STEP_5" AS (SELECT *, CAST(COALESCE("pnl_calc_ebit", 0) + COALESCE("pnl_calc_fp", 0) AS NUMBER(38,6)) AS "pnl_calc_ebt" FROM "STEP_4"),
    "STEP_6" AS (SELECT *, CAST(LEAST(COALESCE("pnl_calc_ebt", 0) * -0.21,0) AS NUMBER(38,6)) AS "pnl_calc_tax" FROM "STEP_5"),
    "STEP_7" AS (SELECT *, CAST(COALESCE("pnl_calc_ebt", 0) + COALESCE("pnl_calc_tax", 0) AS NUMBER(38,6)) AS "pnl_calc_eat" FROM "STEP_6"),

    "STEP_8" AS (
        SELECT
            "PERIOD",
            "STREDISKO",
            "ZAKAZKA",
            "CINNOST",
            "METRIC_CODE",
            "SUM_PM"
    
        FROM "STEP_7"
        UNPIVOT (
            "SUM_PM" FOR "METRIC_CODE" IN ("pnl_calc_gp", "pnl_calc_gm", "pnl_calc_ebitda","pnl_calc_ebit","pnl_calc_ebitm","pnl_calc_ebt","pnl_calc_tax","pnl_calc_eat")
        )

),*/

    "MONTHLY" AS (
        SELECT
            "METRIC_CODE",
            "PERIOD",
            CAST(
                CEIL(MONTH("PERIOD") / 3) AS NUMBER(1, 0)
            ) AS "QUARTER",
            YEAR("PERIOD") AS "YEAR",
            "STREDISKO",
            "ZAKAZKA",
            "CINNOST",
            "SUM_PM"
        FROM {{ tgt }}
        WHERE "METRIC_CODE" IN ('pnl_calc_gp', 'pnl_calc_gm', 'pnl_calc_ebitda', 'pnl_calc_ebit', 'pnl_calc_ebitm', 'pnl_calc_ebt'  /*, 'pnl_calc_tax', 'pnl_calc_eat' */)

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
        FROM "MONTHLY"
        WHERE "METRIC_CODE" ILIKE 'pnl_%'
    ),
    -- "BS_MONTHLY" AS (
    --     SELECT
    --         "METRIC_CODE",
    --         "PERIOD",
    --         "QUARTER",
    --         "YEAR",
    --         CAST(SUM("SUM_PM") AS NUMBER(18, 6)) AS "SUM_PM"
    --     FROM "MONTHLY"
    --     WHERE "METRIC_CODE" ILIKE 'bs_%'
    --     GROUP BY "METRIC_CODE", "PERIOD", "QUARTER", "YEAR"
    -- ),
    -- "BS_CALC" AS (
    --     SELECT
    --         "METRIC_CODE",
    --         "PERIOD",
    --         "QUARTER",
    --         "YEAR",
    --         '' AS "STREDISKO",
    --         '' AS "ZAKAZKA",
    --         '' AS "CINNOST",
    --         "SUM_PM",
    --         CAST(
    --             SUM("SUM_PM") OVER (
    --                 PARTITION BY "METRIC_CODE", "YEAR", "QUARTER"
    --             ) AS NUMBER(18, 6)
    --         ) AS "SUM_PQ",
    --         CAST(
    --             SUM("SUM_PM") OVER (
    --                 PARTITION BY "METRIC_CODE"
    --                 ORDER BY "PERIOD"
    --                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    --             ) AS NUMBER(18, 6)
    --         ) AS "SUM_YTD"
    --     FROM "BS_MONTHLY"
    -- ),
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
        -- UNION ALL
        -- SELECT
        --     "METRIC_CODE",
        --     "PERIOD",
        --     "QUARTER",
        --     "YEAR",
        --     "STREDISKO",
        --     "ZAKAZKA",
        --     "CINNOST",
        --     "SUM_PM",
        --     "SUM_PQ",
        --     "SUM_YTD"
        -- FROM "BS_CALC"
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
    "SUM_PQ" = "SRC"."SUM_PQ",
    "SUM_YTD" = "SRC"."SUM_YTD"
{% endmacro %}
