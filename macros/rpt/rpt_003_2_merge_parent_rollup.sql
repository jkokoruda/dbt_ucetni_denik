{#- Ported 1:1 from Snowflake transformation "003-Populate RPT_UCETNI_DENIK". Runs as a post-hook on the step's model; tgt = that model. -#}
{% macro rpt_003_2_merge_parent_rollup(tgt) %}
-- Upsert aggregated data from parent metrics
MERGE INTO {{ tgt }} AS "TGT"
USING (
WITH "ITEM_HIER" AS (
    SELECT ITEM_CODE, PARENT_CODE FROM {{ source('l2_input', 'REF_REPORT_ITEM') }}
    UNION ALL
    SELECT ITEM_CODE, PARENT_CODE FROM {{ source('l2_input', 'CFG_REPORT_ITEM') }}
),
"ITEM_ROOT" AS (
    -- anchor: every item maps to itself as a starting point
    SELECT
        ITEM_CODE AS "LEAF_CODE",
        ITEM_CODE AS "CURRENT_CODE",
        PARENT_CODE AS "NEXT_PARENT",
        0 AS "LVL"
    FROM "ITEM_HIER"

    UNION ALL

    -- walk up the tree until PARENT_CODE is NULL
    SELECT
        R."LEAF_CODE",
        H.ITEM_CODE AS "CURRENT_CODE",
        H.PARENT_CODE AS "NEXT_PARENT",
        R."LVL" + 1
    FROM "ITEM_ROOT" R
    JOIN "ITEM_HIER" H
        ON H.ITEM_CODE = R."NEXT_PARENT"
    WHERE R."NEXT_PARENT" IS NOT NULL
),
"ITEM_TOP" AS (
    -- pick, for each leaf, the deepest row reached (= topmost ancestor)
    SELECT
        "LEAF_CODE" AS "ITEM_CODE",
        "CURRENT_CODE" AS "TOP_PARENT_CODE"
    FROM "ITEM_ROOT"
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY "LEAF_CODE" ORDER BY "LVL" DESC
    ) = 1
),
"MONTHLY" AS (
SELECT
            IT.TOP_PARENT_CODE AS "METRIC_CODE",
            "REFRI"."PERIOD" AS "PERIOD",
            CAST(
                CEIL(MONTH(REFRI."PERIOD") / 3) AS NUMBER(1, 0)
            ) AS "QUARTER",
            YEAR(REFRI."PERIOD") AS "YEAR",
            REFRI."STREDISKO" AS "STREDISKO",
            REFRI."ZAKAZKA" AS "ZAKAZKA",
            REFRI."CINNOST" AS "CINNOST",
            CAST(SUM(REFRI."SUM_PM") AS NUMBER(18, 6)) AS "SUM_PM"
		FROM {{ tgt }} AS "REFRI"
        INNER JOIN "ITEM_TOP" AS IT
            ON IT."ITEM_CODE" = REFRI."METRIC_CODE"
                    AND IT.TOP_PARENT_CODE IS NOT NULL
        GROUP BY
            IT.TOP_PARENT_CODE,
            REFRI."PERIOD",
            CAST(
                CEIL(MONTH(REFRI."PERIOD") / 3) AS NUMBER(1, 0)
            ),
            YEAR(REFRI."PERIOD"),
            REFRI."STREDISKO",
            REFRI."ZAKAZKA",
            REFRI."CINNOST"

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
            CAST(SUM("SUM_PM") OVER (
                PARTITION BY "METRIC_CODE", "YEAR", "QUARTER", "STREDISKO", "ZAKAZKA", "CINNOST"
            ) AS NUMBER(18, 6)) AS "SUM_PQ",
            CAST(SUM("SUM_PM") OVER (
                PARTITION BY "METRIC_CODE", "YEAR", "STREDISKO", "ZAKAZKA", "CINNOST"
                ORDER BY "PERIOD"
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS NUMBER(18, 6)) AS "SUM_YTD"
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
    --         CAST(SUM("SUM_PM") OVER (
    --             PARTITION BY "METRIC_CODE", "YEAR", "QUARTER"
    --         ) AS NUMBER(18, 6)) AS "SUM_PQ",
    --         CAST(SUM("SUM_PM") OVER (
    --             PARTITION BY "METRIC_CODE"
    --             ORDER BY "PERIOD"
    --             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    --         ) AS NUMBER(18, 6)) AS "SUM_YTD"
    --     FROM "BS_MONTHLY"
    -- ),
    "COMBINED" AS (
        SELECT
            "METRIC_CODE", "PERIOD", "QUARTER", "YEAR",
            "STREDISKO", "ZAKAZKA", "CINNOST",
            "SUM_PM", "SUM_PQ", "SUM_YTD"
        FROM "PNL_CALC"
        -- UNION ALL
        -- SELECT
        --     "METRIC_CODE", "PERIOD", "QUARTER", "YEAR",
        --     "STREDISKO", "ZAKAZKA", "CINNOST",
        --     "SUM_PM", "SUM_PQ", "SUM_YTD"
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
