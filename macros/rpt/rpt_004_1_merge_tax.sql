{#- Ported 1:1 from Snowflake transformation "004- Recalculate tax in RPT". Runs as a post-hook on the step's model; tgt = that model. -#}
{% macro rpt_004_1_merge_tax(tgt) %}
-- 1. Calculate and merge tax: pnl_calc_tax
MERGE INTO {{ tgt }} AS tgt
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
        FROM {{ tgt }}
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
            src.TAX_PM, src.TAX_PQ, src.TAX_YTD, '', '', '')
{% endmacro %}
