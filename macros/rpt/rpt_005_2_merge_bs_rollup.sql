{#- Ported 1:1 from Snowflake transformation "005-Populate RPT_UCETNI_DENIK (BS)". Runs as a post-hook on the step's model; tgt = that model. -#}
{% macro rpt_005_2_merge_bs_rollup(tgt) %}
-- Upsert aggregated data from parent metrics
MERGE INTO {{ tgt }} AS "TGT"
USING (
    WITH "ITEM_HIER" AS (
    SELECT ITEM_CODE, PARENT_CODE FROM {{ source('l2_input', 'REF_REPORT_ITEM') }}
    UNION ALL
    SELECT ITEM_CODE, PARENT_CODE FROM {{ source('l2_input', 'CFG_REPORT_ITEM') }}
),

-- Build full ancestor closure: for every item, list itself + all ancestors up the tree
"ITEM_CLOSURE" AS (
    -- Anchor: every item is its own ancestor at depth 0
    SELECT
        ITEM_CODE,
        ITEM_CODE AS ANCESTOR_CODE,
        0 AS "DEPTH"
    FROM "ITEM_HIER"

    UNION ALL

    -- Recursive: walk upward to parents, grandparents, etc.
    SELECT
        C.ITEM_CODE,
        H.PARENT_CODE AS ANCESTOR_CODE,
        C."DEPTH" + 1
    FROM "ITEM_CLOSURE" C
    JOIN "ITEM_HIER" H
        ON C.ANCESTOR_CODE = H.ITEM_CODE
    WHERE H.PARENT_CODE IS NOT NULL
),

"MONTHLY" AS (
    SELECT
        IC.ANCESTOR_CODE AS "METRIC_CODE",
        "REFRI"."PERIOD" AS "PERIOD",
        CAST(
            CEIL(MONTH(REFRI."PERIOD") / 3) AS NUMBER(1, 0)
        ) AS "QUARTER",
        YEAR(REFRI."PERIOD") AS "YEAR",
        CAST(SUM(REFRI."SUM_PM") AS NUMBER(18, 6)) AS "SUM_PM"
    FROM {{ tgt }} AS "REFRI"
    INNER JOIN "ITEM_CLOSURE" AS IC
        ON IC.ITEM_CODE = REFRI."METRIC_CODE" AND REFRI.METRIC_CODE ILIKE 'bs_%'
    GROUP BY
        IC.ANCESTOR_CODE,
        REFRI."PERIOD",
        CAST(
            CEIL(MONTH(REFRI."PERIOD") / 3) AS NUMBER(1, 0)
        ),
        YEAR(REFRI."PERIOD")
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
            CAST(SUM("SUM_PM") OVER (
                PARTITION BY "METRIC_CODE", "YEAR", "QUARTER"
            ) AS NUMBER(18, 6)) AS "SUM_PQ",
            CAST(SUM("SUM_PM") OVER (
                PARTITION BY "METRIC_CODE"
                ORDER BY "PERIOD"
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS NUMBER(18, 6)) AS "SUM_YTD"
        FROM "MONTHLY"
    )    
SELECT * FROM BS_CALC
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
