/* ===== BLOCK: Blocks ===== */

/* ===== CODE: Populate RPT_UCETNI_DENIK from AGG and map ===== */

-- Ensure table exists with proper structure
-- CREATE TABLE IF NOT EXISTS "RPT_UCETNI_DENIK" (
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
MERGE INTO "RPT_UCETNI_DENIK" AS "TGT"
USING (
    WITH "MONTHLY_RAW" AS (
    -- Raw aggregation from source; no period gaps filled yet
    SELECT
        "MUI"."ITEM_CODE"                                       AS "METRIC_CODE",
        "AGUD"."PERIOD"                                         AS "PERIOD",
        CAST(CEIL(MONTH("AGUD"."PERIOD") / 3) AS NUMBER(1, 0)) AS "QUARTER",
        YEAR("AGUD"."PERIOD")                                   AS "YEAR",
        COALESCE("AGUD"."STREDISKO",'')                                      AS "STREDISKO",
        COALESCE("AGUD"."ZAKAZKA",'')                                        AS "ZAKAZKA",
        COALESCE("AGUD"."CINNOST",'')                                        AS "CINNOST",
        CAST(
            SUM(
                CASE
                    WHEN "MUI"."ITEM_CODE" ILIKE 'bs_%'
                        THEN "AGUD"."SUM_TUZ" * -1
                    ELSE "AGUD"."SUM_TUZ"
                END
            ) AS NUMBER(18, 6)
        )                                                       AS "SUM_PM"
    FROM "AGG_UCETNI_DENIK" AS "AGUD"
    INNER JOIN "MAP_UCET_ITEM" AS "MUI"
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
);

/* ===== CODE: Populate with aggregated data ===== */

-- Upsert aggregated data from parent metrics
MERGE INTO "RPT_UCETNI_DENIK" AS "TGT"
USING (
WITH "ITEM_HIER" AS (
    SELECT ITEM_CODE, PARENT_CODE FROM "REF_REPORT_ITEM"
    UNION ALL
    SELECT ITEM_CODE, PARENT_CODE FROM "CFG_REPORT_ITEM"
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
		FROM "RPT_UCETNI_DENIK" AS "REFRI"
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
);

/* ===== CODE: Populate RPT_UCETNI_DENIK compute and unpivot ===== */

MERGE INTO RPT_UCETNI_DENIK AS t
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
            
    	FROM "RPT_UCETNI_DENIK"
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
VALUES (s."PERIOD", s."QUARTER", s."YEAR", s."STREDISKO", s."ZAKAZKA", s."CINNOST", s."METRIC_CODE", s."SUM_PM");

/* ===== CODE: Populate RTP with PQ and YTD from preceding query ===== */

MERGE INTO "RPT_UCETNI_DENIK" AS "TGT"
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
            
    	FROM "RPT_UCETNI_DENIK"
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
        FROM "RPT_UCETNI_DENIK"
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
    "SUM_YTD" = "SRC"."SUM_YTD";

/* ===== BLOCK: Block 1 ===== */

/* ===== CODE: Code 1 ===== */

-- 1. Calculate and merge tax: pnl_calc_tax
MERGE INTO RPT_UCETNI_DENIK AS tgt
USING (
    WITH tax_calc AS (
        SELECT
            YEAR,
            PERIOD,
            CAST(CEIL(MONTH("PERIOD") / 3) AS NUMBER(1, 0)) AS QUARTER,
            SUM(SUM_PM)  AS EBT_PM,
            SUM(SUM_PQ)  AS EBT_PQ,
            SUM(SUM_YTD) AS EBT_YTD,
            GREATEST(SUM(SUM_YTD), 0) * -0.21 AS TAX_YTD
        FROM RPT_UCETNI_DENIK
        WHERE METRIC_CODE = 'pnl_calc_ebt'
        GROUP BY YEAR, PERIOD
    ),
    tax_month AS (
        SELECT
            YEAR,
            PERIOD,
            QUARTER,
            EBT_PM,
            EBT_PQ,
            EBT_YTD,
            TAX_YTD,
            TAX_YTD - COALESCE(
                LAG(TAX_YTD) OVER (PARTITION BY YEAR ORDER BY PERIOD),
                0
            ) AS TAX_PM
        FROM tax_calc
    )
    SELECT
        YEAR,
        PERIOD,
        QUARTER,
        EBT_PM,
        EBT_PQ,
        EBT_YTD,
        TAX_YTD,
        TAX_PM,
        SUM(TAX_PM) OVER (
            PARTITION BY YEAR, QUARTER
        ) AS TAX_PQ,
        '' AS STREDISKO,
        '' AS ZAKAZKA,
        '' AS CINNOST
    FROM tax_month
) AS src
ON  tgt.METRIC_CODE  = 'pnl_calc_tax'
    AND tgt.YEAR     = src.YEAR
    AND tgt.PERIOD   = src.PERIOD
    AND tgt.STREDISKO = ''
    AND tgt.ZAKAZKA   = ''
    AND tgt.CINNOST   = ''
WHEN MATCHED THEN
    UPDATE SET
        tgt.SUM_PM  = src.TAX_PM,
        tgt.SUM_PQ  = src.TAX_PQ,
        tgt.SUM_YTD = src.TAX_YTD
WHEN NOT MATCHED THEN
    INSERT (METRIC_CODE, YEAR, PERIOD, QUARTER, SUM_PM, SUM_PQ, SUM_YTD, STREDISKO, ZAKAZKA, CINNOST)
    VALUES ('pnl_calc_tax', src.YEAR, src.PERIOD, src.QUARTER,
            src.TAX_PM, src.TAX_PQ, src.TAX_YTD, '', '', '');

-- 2. Calculate and merge EAT: pnl_calc_eat = pnl_calc_ebt + pnl_calc_tax
MERGE INTO RPT_UCETNI_DENIK AS tgt
USING (
    WITH ebt_agg AS (
        -- EBT rows are split across STREDISKO/ZAKAZKA/CINNOST,
        -- so we aggregate to YEAR, PERIOD.
        -- SUM_PQ in the source already holds the quarter-to-date value,
        -- so we take it directly — no additional window function needed.
        SELECT
            YEAR,
            PERIOD,
            CAST(CEIL(MONTH("PERIOD") / 3) AS NUMBER(1, 0)) AS QUARTER,
            SUM(SUM_PM)  AS EBT_PM,
            SUM(SUM_PQ)  AS EBT_PQ,   -- already quarterly sum; used as-is
            SUM(SUM_YTD) AS EBT_YTD
        FROM RPT_UCETNI_DENIK
        WHERE METRIC_CODE = 'pnl_calc_ebt'
        GROUP BY YEAR, PERIOD
    ),
    tax_agg AS (
        SELECT
            YEAR,
            PERIOD,
            SUM_PM  AS TAX_PM,
            SUM_PQ  AS TAX_PQ,
            SUM_YTD AS TAX_YTD
        FROM RPT_UCETNI_DENIK
        WHERE METRIC_CODE = 'pnl_calc_tax'
          AND STREDISKO = ''
          AND ZAKAZKA   = ''
          AND CINNOST   = ''
    )
    SELECT
        e.YEAR,
        e.PERIOD,
        e.QUARTER,
        e.EBT_PM  + COALESCE(t.TAX_PM,  0) AS EAT_PM,
        e.EBT_PQ  + COALESCE(t.TAX_PQ,  0) AS EAT_PQ,   -- EBT_PQ is already quarterly
        e.EBT_YTD + COALESCE(t.TAX_YTD, 0) AS EAT_YTD,
        '' AS STREDISKO,
        '' AS ZAKAZKA,
        '' AS CINNOST
    FROM ebt_agg e
    LEFT JOIN tax_agg t
           ON t.YEAR   = e.YEAR
          AND t.PERIOD = e.PERIOD
) AS src
ON  tgt.METRIC_CODE  = 'pnl_calc_eat'
    AND tgt.YEAR     = src.YEAR
    AND tgt.PERIOD   = src.PERIOD
    AND tgt.STREDISKO = ''
    AND tgt.ZAKAZKA   = ''
    AND tgt.CINNOST   = ''
WHEN MATCHED THEN
    UPDATE SET
        tgt.SUM_PM  = src.EAT_PM,
        tgt.SUM_PQ  = src.EAT_PQ,
        tgt.SUM_YTD = src.EAT_YTD
WHEN NOT MATCHED THEN
    INSERT (METRIC_CODE, YEAR, PERIOD, QUARTER, SUM_PM, SUM_PQ, SUM_YTD, STREDISKO, ZAKAZKA, CINNOST)
    VALUES ('pnl_calc_eat', src.YEAR, src.PERIOD, src.QUARTER,
            src.EAT_PM, src.EAT_PQ, src.EAT_YTD, '', '', '');

/* ===== BLOCK: Blocks ===== */

/* ===== CODE: RPT populate bs_calc_cye ===== */

MERGE INTO "RPT_UCETNI_DENIK" AS "TGT"
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
        FROM "RPT_UCETNI_DENIK"
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
  );

/* ===== CODE: Populate with aggregated data ===== */

-- Upsert aggregated data from parent metrics
MERGE INTO "RPT_UCETNI_DENIK" AS "TGT"
USING (
    WITH "ITEM_HIER" AS (
    SELECT ITEM_CODE, PARENT_CODE FROM "REF_REPORT_ITEM"
    UNION ALL
    SELECT ITEM_CODE, PARENT_CODE FROM "CFG_REPORT_ITEM"
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
    FROM "RPT_UCETNI_DENIK" AS "REFRI"
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
);

/* ===== BLOCK: Block 1 ===== */

/* ===== CODE: Code 1 ===== */

UPDATE RPT_UCETNI_DENIK target
SET
    SUM_LM    = src.SUM_LM,
    SUM_LQ    = src.SUM_LQ,
    SUM_LYTD  = src.SUM_LYTD,
    SUM_LYM   = src.SUM_LYM,
    DIFF_LM   = src.DIFF_LM,
    DIFF_LQ   = src.DIFF_LQ,
    DIFF_LYTD = src.DIFF_LYTD,
    DIFF_LYM  = src.DIFF_LYM,
    PCH_LM    = src.PCH_LM,
    PCH_LQ    = src.PCH_LQ,
    PCH_LYTD  = src.PCH_LYTD,
    PCH_LYM   = src.PCH_LYM
FROM (
    SELECT
        cur.METRIC_CODE,
        cur.PERIOD,
        cur.STREDISKO,
        cur.ZAKAZKA,
        cur.CINNOST,

        lm.SUM_PM  AS SUM_LM,
        lq.SUM_PQ  AS SUM_LQ,
        ly.SUM_YTD AS SUM_LYTD,
        ly.SUM_PM  AS SUM_LYM,

        cur.SUM_PM  - lm.SUM_PM  AS DIFF_LM,
        cur.SUM_PQ  - lq.SUM_PQ  AS DIFF_LQ,
        cur.SUM_YTD - ly.SUM_YTD AS DIFF_LYTD,
        cur.SUM_PM  - ly.SUM_PM  AS DIFF_LYM,

        (cur.SUM_PM - lm.SUM_PM) / NULLIF(ABS(lm.SUM_PM), 0) * 100 AS PCH_LM,
        (cur.SUM_PQ - lq.SUM_PQ) / NULLIF(ABS(lq.SUM_PQ), 0) * 100 AS PCH_LQ,
        (cur.SUM_YTD - ly.SUM_YTD) / NULLIF(ABS(ly.SUM_YTD), 0) * 100 AS PCH_LYTD,
        (cur.SUM_PM - ly.SUM_PM) / NULLIF(ABS(ly.SUM_PM), 0) * 100 AS PCH_LYM

    FROM RPT_UCETNI_DENIK cur

    LEFT JOIN RPT_UCETNI_DENIK lm
           ON lm.METRIC_CODE IS NOT DISTINCT FROM cur.METRIC_CODE
          AND lm.STREDISKO   IS NOT DISTINCT FROM cur.STREDISKO
          AND lm.ZAKAZKA     IS NOT DISTINCT FROM cur.ZAKAZKA
          AND lm.CINNOST     IS NOT DISTINCT FROM cur.CINNOST
          AND lm.PERIOD = DATEADD(month, -1, cur.PERIOD)

    LEFT JOIN RPT_UCETNI_DENIK lq
           ON lq.METRIC_CODE IS NOT DISTINCT FROM cur.METRIC_CODE
          AND lq.STREDISKO   IS NOT DISTINCT FROM cur.STREDISKO
          AND lq.ZAKAZKA     IS NOT DISTINCT FROM cur.ZAKAZKA
          AND lq.CINNOST     IS NOT DISTINCT FROM cur.CINNOST
          AND lq.PERIOD = DATEADD(quarter, -1, cur.PERIOD)

    LEFT JOIN RPT_UCETNI_DENIK ly
           ON ly.METRIC_CODE IS NOT DISTINCT FROM cur.METRIC_CODE
          AND ly.STREDISKO   IS NOT DISTINCT FROM cur.STREDISKO
          AND ly.ZAKAZKA     IS NOT DISTINCT FROM cur.ZAKAZKA
          AND ly.CINNOST     IS NOT DISTINCT FROM cur.CINNOST
          AND ly.PERIOD = DATEADD(year, -1, cur.PERIOD)
) src
WHERE target.METRIC_CODE IS NOT DISTINCT FROM src.METRIC_CODE
  AND target.STREDISKO   IS NOT DISTINCT FROM src.STREDISKO
  AND target.ZAKAZKA     IS NOT DISTINCT FROM src.ZAKAZKA
  AND target.CINNOST     IS NOT DISTINCT FROM src.CINNOST
  AND target.PERIOD = src.PERIOD;

/* ===== BLOCK: Block 1 ===== */

/* ===== CODE: Code 1 ===== */

-- ALTER TABLE RPT_UCETNI_DENIK
-- ADD COLUMN SUM_AVG3M  NUMBER(18, 6),
--     SUM_AVG6M  NUMBER(18, 6),
--     SUM_AVG12M  NUMBER(18, 6);

UPDATE RPT_UCETNI_DENIK target
SET
    SUM_AVG3M  = src.SUM_AVG3M,
    SUM_AVG6M  = src.SUM_AVG6M,
    SUM_AVG12M = src.SUM_AVG12M
FROM (
    SELECT
        METRIC_CODE,
        PERIOD,
        STREDISKO,
        ZAKAZKA,
        CINNOST,

        CASE WHEN COUNT(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
             ) = 3
             THEN AVG(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
             )
        END AS SUM_AVG3M,

        CASE WHEN COUNT(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
             ) = 6
             THEN AVG(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
             )
        END AS SUM_AVG6M,

        CASE WHEN COUNT(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING
             ) = 12
             THEN AVG(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING
             )
        END AS SUM_AVG12M

    FROM RPT_UCETNI_DENIK
) src
WHERE target.METRIC_CODE IS NOT DISTINCT FROM src.METRIC_CODE
  AND target.STREDISKO   IS NOT DISTINCT FROM src.STREDISKO
  AND target.ZAKAZKA     IS NOT DISTINCT FROM src.ZAKAZKA
  AND target.CINNOST     IS NOT DISTINCT FROM src.CINNOST
  AND target.PERIOD = src.PERIOD;

