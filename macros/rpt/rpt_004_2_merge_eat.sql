{#- Ported 1:1 from Snowflake transformation "004- Recalculate tax in RPT". Runs as a post-hook on the step's model; tgt = that model. -#}
{% macro rpt_004_2_merge_eat(tgt) %}
-- 2. Calculate and merge EAT: pnl_calc_eat = pnl_calc_ebt + pnl_calc_tax
MERGE INTO {{ tgt }} AS tgt
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
        FROM {{ tgt }}
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
        FROM {{ tgt }}
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
            src.EAT_PM, src.EAT_PQ, src.EAT_YTD, '', '', '')
{% endmacro %}
