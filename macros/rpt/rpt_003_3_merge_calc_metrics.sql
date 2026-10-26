{#- Ported 1:1 from Snowflake transformation "003-Populate RPT_UCETNI_DENIK". Runs as a post-hook on the step's model; tgt = that model. -#}
{% macro rpt_003_3_merge_calc_metrics(tgt) %}
MERGE INTO {{ tgt }} AS t
USING (
  WITH
    "PIVOTED" AS (
        SELECT
            "PERIOD",
            "STREDISKO", "ZAKAZKA", "CINNOST",
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

    //"STEP_6" AS (SELECT *, CAST(COALESCE("pnl_calc_ebt", 0) AS NUMBER(38,6)) AS "bs_calc_cye" FROM "STEP_5"),  
    //"STEP_6" AS (SELECT *, CAST(LEAST(COALESCE("pnl_calc_ebt", 0) * -0.21,0) AS NUMBER(38,6)) AS "pnl_calc_tax" FROM "STEP_5"),
    //"STEP_7" AS (SELECT *, CAST(COALESCE("pnl_calc_ebt", 0) + COALESCE("pnl_calc_tax", 0) AS NUMBER(38,6)) AS "pnl_calc_eat" FROM "STEP_6"),

    "STEP_8" AS (
        SELECT
            "PERIOD",
            CAST(
                CEIL(MONTH("PERIOD") / 3) AS NUMBER(1, 0)
            ) AS "QUARTER",
            YEAR("PERIOD") AS "YEAR",
            "STREDISKO",
            "ZAKAZKA",
            "CINNOST",
            "METRIC_CODE",
            "SUM_PM"
    
        FROM "STEP_5"
        UNPIVOT (
            "SUM_PM" FOR "METRIC_CODE" IN ("pnl_calc_gp", "pnl_calc_gm", "pnl_calc_ebitda","pnl_calc_ebit","pnl_calc_ebitm","pnl_calc_ebt"
        //,"pnl_calc_tax","pnl_calc_eat"
        )
        )
    )
  
    SELECT * FROM "STEP_8"
) AS s
ON t."PERIOD" = s."PERIOD"
   AND t."STREDISKO" = s."STREDISKO"
   AND t."ZAKAZKA" = s."ZAKAZKA"
   AND t."CINNOST" = s."CINNOST"
   AND t."METRIC_CODE" = s."METRIC_CODE"
WHEN MATCHED THEN UPDATE SET t."SUM_PM" = s."SUM_PM"
WHEN NOT MATCHED THEN INSERT ("PERIOD", "QUARTER", "YEAR", "STREDISKO", "ZAKAZKA", "CINNOST", "METRIC_CODE", "SUM_PM")
VALUES (s."PERIOD", s."QUARTER", s."YEAR", s."STREDISKO", s."ZAKAZKA", s."CINNOST", s."METRIC_CODE", s."SUM_PM")
{% endmacro %}
